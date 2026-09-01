; =============================================================================
; NETWORK TRANSPORT DISPATCH
; =============================================================================

TRANSPORT_USERPORT = 0
TRANSPORT_ULTIMATE = 1

transport_init:
        jsr ultimate_detect
        bne ti_userport
        lda #TRANSPORT_ULTIMATE
        sta zp_transport
        lda #0
        sta zp_rx_head
        rts
ti_userport:
        lda #TRANSPORT_USERPORT
        sta zp_transport
        jmp serial_init

; Input: zp_ptr1 -> HOST:PORT. Returns A=0 on success.
transport_connect:
        lda zp_transport
        beq tc_modem
        jmp ultimate_connect
tc_modem:
        ; Zimodem resets to command mode before every new connection. That reset
        ; points zp_ptr1 at its own command string and never puts it back, so
        ; the caller's HOST:PORT has to be parked across the call — otherwise
        ; the dial that follows walks whatever the reset left behind.
        lda zp_ptr1
        sta tc_saved_ptr
        lda zp_ptr1+1
        sta tc_saved_ptr+1
        jsr modem_reset
        cmp #0
        bne tc_failed
        jsr delay_250ms
        lda tc_saved_ptr
        sta zp_ptr1
        lda tc_saved_ptr+1
        sta zp_ptr1+1
        jmp modem_dial
tc_failed:
        lda #1
        rts

tc_saved_ptr:
        !byte 0, 0

transport_send_frame:
        lda zp_transport
        beq tsf_serial
        jmp ultimate_send_frame
tsf_serial:
        sei                     ; One frame, one uninterrupted burst.
        ldx #0
tsf_tx_loop:
        lda SERIAL_TX_BUF,x
        jsr serial_send_byte
        inx
        cpx #RUBP_MSG_SIZE
        bne tsf_tx_loop
        cli
        lda #0
        rts

transport_available:
        lda zp_transport
        beq ta_serial
        jmp ultimate_available
ta_serial:
        jmp serial_available

transport_receive_frame:
        lda zp_transport
        beq trf_serial
        jmp ultimate_receive_frame
trf_serial:
        sei

        ; Resynchronise on the frame magic rather than trusting the stream to
        ; stay aligned. A bit-banged UART loses or gains a byte from time to
        ; time; without this, one lost byte shifts every frame that follows for
        ; the rest of the session, and the client never parses another message
        ; even though the host is talking perfectly. Scanning for "RACH" costs
        ; nothing when the stream is clean and recovers by itself when it is
        ; not.
        ldx #0                  ; bytes of the magic matched so far
trf_sync:
        jsr serial_recv_byte
        cmp rubp_magic,x
        beq trf_advance

        ; No match. The byte may still be the start of the next magic, so try
        ; it against the first letter before giving up on it entirely.
        ldx #0
        cmp rubp_magic
        bne trf_sync
trf_advance:
        sta SERIAL_RX_BUF,x
        inx
        cpx #4
        bcc trf_sync

        ; Header magic in hand; the rest of the frame follows it.
trf_rx_loop:
        jsr serial_recv_byte
        sta SERIAL_RX_BUF,x
        inx
        cpx #RUBP_MSG_SIZE
        bcc trf_rx_loop
        cli
        lda #0
        rts

rubp_magic:
        !text "RACH"
