; =============================================================================
; INTERRUPT-DRIVEN RECEIVE
; =============================================================================
; The adapter ties the modem's data line to /FLAG2 as well as PB0, so the
; falling edge that opens a byte raises a CIA #2 interrupt — which on this
; machine is an NMI. That is the whole reason the pin is wired that way, and
; using it is the difference between a client that catches a frame and one that
; happens to be looking.
;
; Polling could not work here. A frame is 64 bytes at 2400 baud, a quarter of a
; second, and the host sends GAME_STATE and HAND_SYNC back to back. Any slow
; work — redrawing the screen, most obviously — falls in the gap and the frame
; is gone, every time rather than occasionally. The host then waits for an
; acknowledgement of a pair the client only ever saw half of, and the client
; waits for a turn that will never come.
;
; So the handler clocks the byte in and drops it in a ring, and the main loop
; reads from the ring whenever it gets round to it. Nothing above this file has
; to be quick.

; A quarter of a kilobyte, which is four whole frames. The host sends the
; recovery pair back to back and the lobby messages in a burst, so a ring that
; holds only two frames overflows while the client is drawing — 75 bytes lost
; in a single connect, measured, with a 128-byte ring. This machine has the
; room; there is no reason to be mean with it.
RX_RING_SIZE    = 256
RX_RING_MASK    = RX_RING_SIZE-1

; -----------------------------------------------------------------------------
; Take over the NMI vector and let /FLAG2 interrupts through.
; Clobbers: A
; -----------------------------------------------------------------------------
serial_rx_init:
        lda #0
        sta rx_ring_head
        sta rx_ring_tail
        sta rx_ring_lost

        sei
        lda #<serial_rx_nmi
        sta $0318
        lda #>serial_rx_nmi
        sta $0319

        ; Clear anything pending, then enable /FLAG2 only.
        lda #$7f
        sta CIA2_ICR            ; disable every CIA #2 source
        lda CIA2_ICR            ; and acknowledge what was outstanding
        lda #%10010000          ; set + FLAG
        sta CIA2_ICR
        cli
        rts

; -----------------------------------------------------------------------------
; Stop taking receive interrupts, so the transmit path can hold the line
; without the handler chasing its own echo.
; Clobbers: A
; -----------------------------------------------------------------------------
serial_rx_disable:
        lda #$10                ; clear + FLAG
        sta CIA2_ICR
        lda CIA2_ICR
        rts

serial_rx_enable:
        lda CIA2_ICR            ; drop anything latched while we were sending
        lda #%10010000
        sta CIA2_ICR
        rts

; -----------------------------------------------------------------------------
; NMI: a byte is starting. Clock it in and ring it.
;
; Interrupts are already masked by the NMI itself. The handler runs for eight
; and a half bit times and returns inside the stop bit, so it is ready for the
; next start edge — which is what lets a 64-byte frame arrive back to back.
; -----------------------------------------------------------------------------
serial_rx_nmi:
        pha
        txa
        pha
        tya
        pha

        ; /FLAG2 is an edge, not a level, and every data bit that falls is an
        ; edge too. Mask it for the length of the byte and re-enable once the
        ; stop bit has passed, so only a start bit brings us back here.
        ;
        ; The status bit cannot be tested to decide whether this was ours: the
        ; bit clock is Timer A on this same chip, and polling its underflow
        ; reads the ICR, which clears every flag in it. RESTORE lands here too
        ; and yields one junk byte, which the frame magic and the CRC discard.
        lda #$10                ; clear + FLAG
        sta CIA2_ICR
        lda CIA2_ICR            ; acknowledge, dropping the NMI line

        jsr serial_recv_bits
        ldx rx_ring_head
        sta rx_ring,x
        inx
        txa
        and #RX_RING_MASK
        cmp rx_ring_tail
        beq .rn_full            ; would collide with the reader: drop it
        sta rx_ring_head
        jmp .rn_done
.rn_full:
        inc rx_ring_lost        ; counted so a full ring is visible, not silent

.rn_done:
        lda CIA2_ICR            ; drop edges latched while the byte came in
        lda #%10010000          ; set + FLAG
        sta CIA2_ICR

        pla
        tay
        pla
        tax
        pla
        rti

; -----------------------------------------------------------------------------
; Is there a byte waiting?
; Out: Z clear when the ring holds something. Clobbers: A.
; -----------------------------------------------------------------------------
serial_rx_ready:
        lda rx_ring_head
        cmp rx_ring_tail
        bne .rr_yes
        lda #0                  ; Z set: nothing waiting
        rts
.rr_yes:
        lda #1
        rts

; -----------------------------------------------------------------------------
; Take the next byte from the ring.
; Out: A = byte, C set. C clear when the ring is empty. Preserves X and Y.
; -----------------------------------------------------------------------------
serial_rx_get:
        ; Frame assembly and modem timeouts keep their index in X.
        txa
        pha
        jsr serial_rx_get_raw
        sta rx_read_byte
        pla
        tax
        lda rx_read_byte
        rts
rx_read_byte: !byte 0
serial_rx_get_raw:
        ldx rx_ring_tail
        cpx rx_ring_head
        beq .rg_empty
        lda rx_ring,x
        pha
        inx
        txa
        and #RX_RING_MASK
        sta rx_ring_tail
        pla
        sec
        rts
.rg_empty:
        lda #0
        clc
        rts

rx_ring_head:   !byte 0
rx_ring_tail:   !byte 0
rx_ring_lost:   !byte 0
rx_ring:        !fill RX_RING_SIZE, 0
