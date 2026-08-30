; =============================================================================
; ULTIMATE COMMAND INTERFACE NETWORK TRANSPORT
; =============================================================================
; Supports the Network Target present in current 1541 Ultimate-II(+),
; Ultimate-II+L, Ultimate 64, and Commodore 64 Ultimate firmware.

UCI_CONTROL     = $df1c         ; write control / read status
UCI_COMMAND     = $df1d         ; write command / read identification
UCI_RESPONSE    = $df1e
UCI_STATUS_DATA = $df1f

UCI_ID          = $c9
UCI_DATA_AV     = $80
UCI_STATUS_AV   = $40
UCI_STATE_MASK  = $30
UCI_STATE_BUSY  = $10
UCI_PUSH_CMD    = $01
UCI_DATA_ACCEPT = $02
UCI_ABORT       = $04
UCI_CLEAR_ERROR = $08

UCI_TARGET_NET  = $03
UCI_OPEN_TCP    = $07
UCI_CLOSE       = $09
UCI_READ        = $10
UCI_WRITE       = $11

ultimate_detect:
        lda UCI_COMMAND
        cmp #UCI_ID
        beq ud_found
        lda #1
        rts
ud_found:
        lda #0
        rts

; Input: zp_ptr1 -> HOST:PORT. Uses AT_CMD_BUF for a separated hostname.
ultimate_connect:
        jsr ultimate_split_address
        cmp #0
        bne uc_failed

        jsr uci_begin
        bne uc_failed
        lda #UCI_TARGET_NET
        sta UCI_COMMAND
        lda #UCI_OPEN_TCP
        sta UCI_COMMAND
        lda zp_temp3            ; port low
        sta UCI_COMMAND
        lda zp_temp4            ; port high
        sta UCI_COMMAND
        ldx #0
uc_host:
        lda AT_CMD_BUF,x
        sta UCI_COMMAND
        beq uc_host_done
        inx
        bne uc_host
uc_host_done:
        jsr uci_execute
        bne uc_failed

        ; OPEN returns one response byte: the socket handle.
        lda UCI_CONTROL
        and #UCI_DATA_AV
        beq uc_failed_accept
        lda UCI_RESPONSE
        sta zp_socket
        jsr uci_drain_data
        jsr uci_status_ok
        pha
        jsr uci_accept
        pla
        rts
uc_failed_accept:
        jsr uci_accept
uc_failed:
        lda #1
        rts

ultimate_send_frame:
        jsr uci_begin
        bne us_failed
        lda #UCI_TARGET_NET
        sta UCI_COMMAND
        lda #UCI_WRITE
        sta UCI_COMMAND
        lda zp_socket
        sta UCI_COMMAND
        ldx #0
us_bytes:
        lda SERIAL_TX_BUF,x
        sta UCI_COMMAND
        inx
        cpx #RUBP_MSG_SIZE
        bne us_bytes
        jsr uci_execute
        bne us_failed

        ; WRITE returns the little-endian number of bytes accepted.
        lda UCI_CONTROL
        and #UCI_DATA_AV
        beq us_failed_accept
        lda UCI_RESPONSE
        cmp #RUBP_MSG_SIZE
        bne us_failed_accept
        lda UCI_RESPONSE
        bne us_failed_accept
        jsr uci_drain_data
        jsr uci_status_ok
        pha
        jsr uci_accept
        pla
        rts
us_failed_accept:
        jsr uci_accept
us_failed:
        lda #1
        rts

; Return convention matches serial_available: A=0/Z=1 means frame ready;
; A=1/Z=0 means no complete frame yet.
ultimate_available:
        lda zp_rx_head
        cmp #RUBP_MSG_SIZE
        beq ua_ready
        jsr ultimate_read_chunk
        cmp #0
        bne ua_none
        lda zp_rx_head
        cmp #RUBP_MSG_SIZE
        beq ua_ready
ua_none:
        lda #1
        rts
ua_ready:
        lda #0
        rts

ultimate_receive_frame:
urf_wait:
        jsr ultimate_available
        bne urf_wait
        lda #0
        sta zp_rx_head
        rts

ultimate_read_chunk:
        jsr uci_begin
        bne ur_failed
        lda #UCI_TARGET_NET
        sta UCI_COMMAND
        lda #UCI_READ
        sta UCI_COMMAND
        lda zp_socket
        sta UCI_COMMAND
        lda #RUBP_MSG_SIZE
        sec
        sbc zp_rx_head
        sta zp_temp1            ; requested count
        sta UCI_COMMAND
        lda #0
        sta UCI_COMMAND
        jsr uci_execute
        bne ur_failed

        ; Response begins with actual length (little endian), then bytes.
        lda UCI_CONTROL
        and #UCI_DATA_AV
        beq ur_failed_accept
        lda UCI_RESPONSE
        sta zp_temp2
        lda UCI_RESPONSE
        bne ur_failed_accept
        lda zp_temp2
        cmp zp_temp1
        bcc ur_count_ok
        beq ur_count_ok
        bcs ur_failed_accept
ur_count_ok:
        ldx zp_rx_head
        ldy #0
ur_copy:
        cpy zp_temp2
        beq ur_copied
        lda UCI_CONTROL
        and #UCI_DATA_AV
        beq ur_failed_accept
        lda UCI_RESPONSE
        sta SERIAL_RX_BUF,x
        inx
        iny
        bne ur_copy
ur_copied:
        stx zp_rx_head
        jsr uci_drain_data
        jsr uci_status_ok
        pha
        jsr uci_accept
        pla
        rts
ur_failed_accept:
        jsr uci_accept
ur_failed:
        lda #1
        rts

ultimate_close:
        jsr uci_begin
        bne ucl_failed
        lda #UCI_TARGET_NET
        sta UCI_COMMAND
        lda #UCI_CLOSE
        sta UCI_COMMAND
        lda zp_socket
        sta UCI_COMMAND
        jsr uci_execute
        bne ucl_failed
        jsr uci_drain_data
        jsr uci_status_ok
        pha
        jsr uci_accept
        pla
        rts
ucl_failed:
        lda #1
        rts

; Split HOST:PORT, convert decimal port to 16-bit little endian.
ultimate_split_address:
        ldy #0
usa_copy:
        lda (zp_ptr1),y
        beq usa_missing
        cmp #':'
        beq usa_port
        sta AT_CMD_BUF,y
        iny
        cpy #30
        bcc usa_copy
usa_missing:
        lda #1
        rts
usa_port:
        lda #0
        sta AT_CMD_BUF,y
        sta zp_temp3
        sta zp_temp4
        iny
usa_digit:
        lda (zp_ptr1),y
        beq usa_done
        cmp #'0'
        bcc usa_missing
        cmp #('9'+1)
        bcs usa_missing
        sec
        sbc #'0'
        pha
        ; port = port * 10 + digit, using a 16-bit shift/add.
        lda zp_temp3
        sta zp_rx_tail
        lda zp_temp4
        sta zp_tx_tail
        asl zp_temp3
        rol zp_temp4            ; *2
        asl zp_temp3
        rol zp_temp4            ; *4
        clc
        lda zp_temp3
        adc zp_rx_tail
        sta zp_temp3
        lda zp_temp4
        adc zp_tx_tail
        sta zp_temp4            ; *5
        asl zp_temp3
        rol zp_temp4            ; *10
        pla
        clc
        adc zp_temp3
        sta zp_temp3
        bcc usa_next
        inc zp_temp4
usa_next:
        iny
        bne usa_digit
usa_done:
        lda zp_temp3
        ora zp_temp4
        beq usa_missing
        lda #0
        rts

; Wait for an idle command interface, with a bounded timeout.
uci_begin:
        ldx #0
        ldy #0
ub_wait:
        lda UCI_CONTROL
        and #UCI_STATE_MASK
        beq ub_ok
        inx
        bne ub_wait
        iny
        bne ub_wait
        lda #UCI_ABORT
        sta UCI_CONTROL
        lda #1
        rts
ub_ok:
        lda #0
        rts

; Push the command and wait for the busy state to finish.
uci_execute:
        lda #UCI_PUSH_CMD
        sta UCI_CONTROL
        ldx #0
        ldy #0
ue_wait:
        lda UCI_CONTROL
        and #UCI_STATE_MASK
        cmp #UCI_STATE_BUSY
        bne ue_done
        inx
        bne ue_wait
        iny
        bne ue_wait
        lda #UCI_ABORT
        sta UCI_CONTROL
        lda #1
        rts
ue_done:
        lda UCI_CONTROL
        and #$08                ; interface state-error flag
        beq ue_ok
        lda #UCI_CLEAR_ERROR
        sta UCI_CONTROL
        lda #1
        rts
ue_ok:
        lda #0
        rts

uci_drain_data:
        lda UCI_CONTROL
        and #UCI_DATA_AV
        beq udd_done
        lda UCI_RESPONSE
        jmp uci_drain_data
udd_done:
        rts

; Drain the textual status and accept only a leading "00".
uci_status_ok:
        lda #$ff
        sta zp_temp1
        sta zp_temp2
        ldx #0
uso_loop:
        lda UCI_CONTROL
        and #UCI_STATUS_AV
        beq uso_done
        lda UCI_STATUS_DATA
        cpx #0
        bne uso_second
        sta zp_temp1
        inx
        jmp uso_loop
uso_second:
        cpx #1
        bne uso_loop
        sta zp_temp2
        inx
        jmp uso_loop
uso_done:
        lda zp_temp1
        cmp #'0'
        bne uso_failed
        lda zp_temp2
        cmp #'0'
        bne uso_failed
        lda #0
        rts
uso_failed:
        lda #1
        rts

uci_accept:
        lda #UCI_DATA_ACCEPT
        sta UCI_CONTROL
        rts
