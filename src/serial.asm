; =============================================================================
; SERIAL MODULE
; =============================================================================
; Bit-banged serial communication via User Port at 2400 baud
;
; Interrupt policy: each routine masks interrupts for the byte it is clocking
; and restores the caller's state afterwards, rather than unconditionally
; re-enabling. A whole 64-byte frame takes a quarter of a second on this link,
; which is fifteen or more KERNAL interrupts; masking only within a byte leaves
; every inter-byte gap open to a jiffy IRQ that arrives mid-start-bit. Callers
; that move a frame hold `sei` across the whole thing, and php/plp is what lets
; them.
;
; Hardware:
;   CIA2 ($DD00-$DD0F) controls the User Port
;   PA2 = TXD (directly toggleable via CIA2_PRA bit 2)
;   PB0/FLAG2 = RXD on the Sven Petersen Rev. 2 user-port board
;
; Timing:
;   2400 baud = 416.67 cycles per bit at 1MHz
;   We use ~410 cycles accounting for instruction overhead

; -----------------------------------------------------------------------------
; CIA2 Register Addresses
; -----------------------------------------------------------------------------

CIA2_PRA        = $dd00         ; Port A data register
CIA2_PRB        = $dd01         ; Port B data register
CIA2_DDRA       = $dd02         ; Data direction register A
CIA2_DDRB       = $dd03         ; Data direction register B
CIA2_ICR        = $dd0d         ; Interrupt control register

; -----------------------------------------------------------------------------
; User Port Bit Masks
; -----------------------------------------------------------------------------

TXD_BIT         = %00000100     ; PA2 - transmit data (active low)
RXD_BIT         = %00000001     ; PB0 - modem TXD (also wired to FLAG2)

; -----------------------------------------------------------------------------
; Timing Constants
; -----------------------------------------------------------------------------
; At 1MHz, 2400 baud = 1000000 / 2400 = 416.67 cycles per bit
; The delay loop: LDY + DEY*N + BNE = 2 + 5*N + 3 = 5 + 5*N cycles
; For N=82: 5 + 410 = 415 cycles (close enough)

BIT_DELAY_COUNT = 82            ; ~415 cycles
HALF_BIT_DELAY  = 41            ; ~210 cycles (sample in middle of bit)

; =============================================================================
; SERIAL SUBROUTINES
; =============================================================================

; -----------------------------------------------------------------------------
; Initialize User Port for serial communication
; Sets PA2 as output (TXD), starts in idle (high) state
; -----------------------------------------------------------------------------
serial_init:
        ; Set PA2 as output
        lda CIA2_DDRA
        ora #TXD_BIT            ; PA2 = output
        sta CIA2_DDRA

        ; PB0 is the modem-to-C64 data line and must remain an input.
        lda CIA2_DDRB
        and #%11111110
        sta CIA2_DDRB

        ; Set TXD high (idle state, marking)
        lda CIA2_PRA
        ora #TXD_BIT            ; PA2 = high
        sta CIA2_PRA

        rts

; -----------------------------------------------------------------------------
; Send one byte over serial (blocking)
; Input: A = byte to send
; Clobbers: A, X, Y, zp_temp1
;
; Serial format: 1 start bit, 8 data bits (LSB first), 1 stop bit
; Start bit = low, Stop bit = high
; -----------------------------------------------------------------------------
serial_send_byte:
        sta zp_temp1            ; Save byte before A is used to save X/Y.
        txa
        pha
        tya
        pha
        php                     ; Keep the caller's interrupt state...
        sei                     ; ...while this byte is clocked out
        ldx #8                  ; 8 data bits

        ; === Start bit (low) ===
        lda CIA2_PRA
        and #%11111011          ; PA2 = low (clear bit 2)
        sta CIA2_PRA
        jsr serial_bit_delay

        ; === Data bits (LSB first) ===
.send_loop:
        lsr zp_temp1            ; Shift LSB into carry
        lda CIA2_PRA
        bcc .send_zero
        ora #TXD_BIT            ; Carry set = send high (1)
        bne .send_store         ; (always branches)
.send_zero:
        and #%11111011          ; Carry clear = send low (0)
.send_store:
        sta CIA2_PRA
        jsr serial_bit_delay
        dex
        bne .send_loop

        ; === Stop bit (high) ===
        lda CIA2_PRA
        ora #TXD_BIT            ; PA2 = high
        sta CIA2_PRA
        jsr serial_bit_delay

        plp                     ; Restore, so a frame-wide sei survives
        pla
        tay
        pla
        tax
        rts

; -----------------------------------------------------------------------------
; Receive one byte over serial (blocking)
; Returns: A = received byte
; Clobbers: A, X, Y, zp_temp1
;
; Waits for start bit, then samples 8 data bits in the middle of each
; -----------------------------------------------------------------------------
serial_recv_byte:
        txa
        pha
        tya
        pha
        php
        sei
        lda #0
        sta zp_temp1            ; Clear result

        ; === Wait for start bit (high to low transition) ===
.wait_start:
        lda CIA2_PRB
        and #RXD_BIT
        bne .wait_start         ; Loop while high

        ; Half bit delay to sample in middle of bits
        jsr serial_half_delay

        ; === Sample 8 data bits ===
        ldx #8
.recv_bit:
        jsr serial_bit_delay    ; Wait for next bit

        lda CIA2_PRB
        and #RXD_BIT            ; Isolate RXD bit
        clc
        beq .bit_low            ; Branch if bit is low
        sec                     ; Bit is high, set carry
.bit_low:
        ror zp_temp1            ; Rotate carry into MSB (builds byte LSB first)
        dex
        bne .recv_bit

        ; Wait through stop bit
        jsr serial_bit_delay

        plp
        lda zp_temp1
        sta zp_temp2
        pla
        tay
        pla
        tax
        lda zp_temp2            ; Return received byte
        rts

; -----------------------------------------------------------------------------
; Check if data is available (start bit detected)
; Returns: Z=1 if no data (line idle/high), Z=0 if start bit detected
; Clobbers: A
; -----------------------------------------------------------------------------
serial_available:
        lda CIA2_PRB
        and #RXD_BIT            ; Check RXD line
        rts                     ; Z=0 if low (start bit), Z=1 if high (idle)

; -----------------------------------------------------------------------------
; Bit timing delay (~415 cycles for 2400 baud)
; Clobbers: Y
; -----------------------------------------------------------------------------
serial_bit_delay:
        ldy #BIT_DELAY_COUNT
-
        dey
        bne -
        rts

; -----------------------------------------------------------------------------
; Half bit delay (~210 cycles, for sampling in middle)
; Clobbers: Y
; -----------------------------------------------------------------------------
serial_half_delay:
        ldy #HALF_BIT_DELAY
-
        dey
        bne -
        rts

; -----------------------------------------------------------------------------
; Send a null-terminated string
; Input: zp_ptr1 = pointer to string
; Clobbers: A, X, Y, zp_temp1
; -----------------------------------------------------------------------------
serial_send_string:
        ldy #0
-
        lda (zp_ptr1),y
        beq +                   ; Null terminator
        jsr serial_send_byte
        iny
        bne -
+
        rts
