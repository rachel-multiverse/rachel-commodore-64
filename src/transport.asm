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
        ; Zimodem resets to command mode before every new connection.
        jsr modem_reset
        cmp #0
        bne tc_failed
        jsr delay_250ms
        jmp modem_dial
tc_failed:
        lda #1
        rts

transport_send_frame:
        lda zp_transport
        beq tsf_serial
        jmp ultimate_send_frame
tsf_serial:
        ldx #0
tsf_tx_loop:
        lda SERIAL_TX_BUF,x
        jsr serial_send_byte
        inx
        cpx #RUBP_MSG_SIZE
        bne tsf_tx_loop
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
        ldx #0
trf_rx_loop:
        jsr serial_recv_byte
        sta SERIAL_RX_BUF,x
        inx
        cpx #RUBP_MSG_SIZE
        bne trf_rx_loop
        lda #0
        rts
