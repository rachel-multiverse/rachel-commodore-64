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

; Status classes returned by uci_status_code. The network target answers in
; ASCII — "00,OK", "01,CONNECTION CLOSED BY HOST", "02,NO DATA" and a spread
; of 8x codes for bad parameters. Only the two leading digits may be matched:
; the firmware appends an errno to several of the lines.
UCI_ST_OK       = 0
UCI_ST_CLOSED   = 1
UCI_ST_NO_DATA  = 2
UCI_ST_ERROR    = 3

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

; Blocking, but not unconditionally: the handshake calls this without first
; asking whether anything is waiting, so a host that hangs up mid-frame would
; otherwise park the machine in here for good.
ultimate_receive_frame:
urf_wait:
        jsr ultimate_available
        beq urf_ready
        lda transport_link_down
        beq urf_wait
        lda #1                  ; the peer went away; there is no frame coming
        rts
urf_ready:
        lda #0
        sta zp_rx_head
        rts

ultimate_read_chunk:
        jsr uci_begin
        beq ur_begin_ok
        ; Near copy of the failure exit: the routine grew past a branch's reach.
ur_fail_near:
        lda #1
        rts
ur_begin_ok:
        lda #UCI_TARGET_NET
        sta UCI_COMMAND
        lda #UCI_READ
        sta UCI_COMMAND
        lda zp_socket
        sta UCI_COMMAND
        lda #RUBP_MSG_SIZE
        sec
        sbc zp_rx_head
        sta UCI_COMMAND         ; requested count, low
        lda #0
        sta UCI_COMMAND         ; requested count, high
        jsr uci_execute
        bne ur_fail_near

        ; Classify the status before touching the response. READ never answers
        ; "00,OK" with an empty payload: a poll that found nothing answers
        ; "02,NO DATA" and leads the response with recv's -1, so the length is
        ; a count only once the status says it is. Demanding "00" here would
        ; report a fault on every quiet poll of real hardware.
        jsr uci_status_code
        cmp #UCI_ST_OK
        beq ur_have_data
        cmp #UCI_ST_NO_DATA
        beq ur_quiet
        cmp #UCI_ST_CLOSED
        beq ur_closed
        jmp ur_failed_accept    ; a parameter was refused

        ; The host hung up. The firmware announces that exactly once — the
        ; socket is dead afterwards and later polls only report no data — so
        ; the fact is latched here rather than left to be noticed again.
ur_closed:
        lda #1
        sta transport_link_down
        jmp ur_failed_accept

        ; Nothing had arrived. The buffer is untouched and the caller simply
        ; has no frame yet, which is the normal state of an idle connection.
ur_quiet:
        jsr uci_drain_data
        jsr uci_accept
        lda #0
        rts

ur_have_data:
        lda UCI_CONTROL
        and #UCI_DATA_AV
        beq ur_failed_accept
        lda UCI_RESPONSE
        sta zp_temp2
        lda UCI_RESPONSE
        bne ur_failed_accept
        ; Refuse more than there is room for rather than run off the buffer.
        lda #RUBP_MSG_SIZE
        sec
        sbc zp_rx_head
        cmp zp_temp2
        bcc ur_failed_accept
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
        jsr uci_accept
        lda #0
        rts
ur_failed_accept:
        jsr uci_drain_data
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

; Drain the textual status and classify its leading two digits.
uci_status_code:
        lda #$ff
        sta zp_temp1
        sta zp_temp2
        ldx #0
usc_loop:
        lda UCI_CONTROL
        and #UCI_STATUS_AV
        beq usc_done
        lda UCI_STATUS_DATA
        cpx #0
        bne usc_second
        sta zp_temp1
        inx
        jmp usc_loop
usc_second:
        cpx #1
        bne usc_loop
        sta zp_temp2
        inx
        jmp usc_loop
usc_done:
        lda zp_temp1
        cmp #'0'
        bne usc_error
        lda zp_temp2
        cmp #'0'
        beq usc_ok
        cmp #'1'
        beq usc_closed
        cmp #'2'
        beq usc_no_data
usc_error:
        lda #UCI_ST_ERROR
        rts
usc_ok:
        lda #UCI_ST_OK
        rts
usc_closed:
        lda #UCI_ST_CLOSED
        rts
usc_no_data:
        lda #UCI_ST_NO_DATA
        rts

; Accept only a leading "00". A=0/Z=1 on success.
uci_status_ok:
        jsr uci_status_code
        cmp #UCI_ST_OK
        beq uso_ok
        lda #1
        rts
uso_ok:
        lda #0
        rts

uci_accept:
        lda #UCI_DATA_ACCEPT
        sta UCI_CONTROL
        rts
