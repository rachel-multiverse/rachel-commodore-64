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
CIA2_TA_LO      = $dd04         ; Timer A low byte
CIA2_TA_HI      = $dd05         ; Timer A high byte
CIA2_ICR        = $dd0d         ; Interrupt control / status
CIA2_CRA        = $dd0e         ; Control register A

; -----------------------------------------------------------------------------
; User Port Bit Masks
; -----------------------------------------------------------------------------

TXD_BIT         = %00000100     ; PA2 - transmit data (active low)
RXD_BIT         = %00000001     ; PB0 - modem TXD (also wired to FLAG2)

; -----------------------------------------------------------------------------
; Timing Constants
; -----------------------------------------------------------------------------
; Sizing the delay is not just the delay loop, and it is not 1MHz.
;
; A bit costs the delay loop plus the instructions around it: about 5N+37
; cycles to send one and 5N+35 to receive one. More importantly the VIC-II
; steals cycles from the CPU for its badlines, so a bit occupies more real time
; than the CPU spends on it — roughly 8% more with the screen on. Baud is real
; time, so that has to be paid for.
;
; PAL phi2 is 985248Hz, so 2400 baud is 410 cycles of real time per bit, which
; is about 377 cycles of CPU time once the VIC-II has taken its share. 5N+36 =
; 377 gives N = 68.
;
; Sized for 415 CPU cycles as if the machine were a bare 1MHz, this client ran
; at roughly 2030 baud while both ends believed 2400 — a 15% error, where 8N1
; tolerates about 5%. It could not have talked to a real modem set to 2400.

; Idle-line budget before serial_recv_byte reports "nothing arrived". Each pass
; of the wait loop is about 11 cycles, so 4500 is roughly 50ms.
RECV_WAIT_LIMIT = 4500

; One bit at 2400 baud, in phi2 cycles: PAL 985248 / 2400.
BIT_PERIOD      = 410
; From the falling edge of the start bit to the middle of bit 0.
FIRST_SAMPLE    = 615

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
        jsr serial_clock_start
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
; Receive one byte over serial
; Returns: A = received byte, C set. C clear means the line stayed idle and no
;          byte arrived.
; Clobbers: A, X, Y, zp_temp1. Deliberately not zp_temp3/zp_temp4: the modem's
; own response timeouts live there and call straight into this routine.
;
; Waits for a start bit, then samples 8 data bits in the middle of each.
;
; The wait is bounded. An unbounded one deadlocks the machine: this routine runs
; with interrupts masked, so a caller that enters it on a false edge — or part
; way through a frame the host never finishes — never comes back, and the host
; is left waiting for a move from a client that has stopped executing. Both
; sides then wait for each other forever.
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

        ; Roughly 50ms of idle line before giving up, which is ten byte times
        ; at this rate: long enough that a host mid-frame is never cut off,
        ; short enough that a false edge costs one main-loop pass.
        lda #<RECV_WAIT_LIMIT
        sta recv_wait_lo
        lda #>RECV_WAIT_LIMIT
        sta recv_wait_hi

        ; === Wait for start bit (high to low transition) ===
.wait_start:
        lda CIA2_PRB
        and #RXD_BIT
        beq .got_start          ; Low: a start bit
        dec recv_wait_lo
        bne .wait_start
        dec recv_wait_hi
        bne .wait_start

        ; Nothing arrived. Report that rather than hanging here.
        plp
        pla
        tay
        pla
        tax
        lda #0
        clc
        rts
.got_start:

        ; Start the bit clock at the middle of bit 0 and let it free-run.
        jsr serial_clock_start_rx

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
        sec
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
; Bit timing, from CIA #2 Timer A.
;
; A counted delay loop cannot hold a bit rate on this machine. The VIC-II stops
; the CPU for its badlines, so the same instructions take different amounts of
; real time depending on where the raster happens to be — and baud is real
; time. Worse, the error moves whenever the surrounding code changes, so a
; driver tuned by experiment stops working the next time anything near it is
; edited. That is exactly what happened here: adding a timeout to the receive
; loop shifted the sampling phase enough to break a link that had been working.
;
; The timer runs free at one bit period and is simply watched. Bit boundaries
; are therefore exactly one period apart no matter how late the CPU notices an
; underflow, so a badline steals margin from a single bit instead of pushing
; every following bit further out of step.
; -----------------------------------------------------------------------------

; Idle-line countdown for serial_recv_byte, in its own storage so the modem's
; response timeouts in zp_temp3/zp_temp4 survive a call into the receiver.
recv_wait_lo: !byte 0
recv_wait_hi: !byte 0

; Start the free-running bit clock, phase-aligned to now.
; Clobbers: A
serial_clock_start:
        lda #<BIT_PERIOD
        sta CIA2_TA_LO
        lda #>BIT_PERIOD
        sta CIA2_TA_HI
        lda #%00010001          ; force load, continuous, start
        sta CIA2_CRA
        lda CIA2_ICR            ; drop any stale underflow
        rts

; Start the bit clock at the middle of the first data bit, then let it run at
; one bit period. The counter is loaded with the longer first interval while
; the latch already holds the bit period, so the automatic reload after the
; first underflow needs no further attention.
; Clobbers: A
serial_clock_start_rx:
        lda #<FIRST_SAMPLE
        sta CIA2_TA_LO
        lda #>FIRST_SAMPLE
        sta CIA2_TA_HI
        lda #%00010001          ; force load, continuous, start
        sta CIA2_CRA
        lda #<BIT_PERIOD        ; latch the ordinary period for every reload
        sta CIA2_TA_LO
        lda #>BIT_PERIOD
        sta CIA2_TA_HI
        lda CIA2_ICR
        rts

; Wait for the next bit boundary.
; Clobbers: A
serial_bit_delay:
.sbd_wait:
        lda CIA2_ICR
        and #$01                ; Timer A underflow
        beq .sbd_wait
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
