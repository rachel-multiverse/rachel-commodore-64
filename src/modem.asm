; =============================================================================
; MODEM MODULE
; =============================================================================
; Hayes AT command handling for Zimodem WiFi bridge
;
; Zimodem accepts standard Hayes commands:
;   ATZ     - Reset modem
;   ATDT    - Dial (connect to TCP host:port)
;   +++     - Escape to command mode
;   ATH     - Hang up
;
; Responses:
;   OK      - Command accepted
;   ERROR   - Command failed
;   CONNECT - TCP connection established
;   NO CARRIER - Connection failed/dropped

; =============================================================================
; MODEM SUBROUTINES
; =============================================================================

; -----------------------------------------------------------------------------
; Send AT command and wait for response
; Input: zp_ptr1 = pointer to command (without "AT" prefix)
; Returns: A = 0 if OK, 1 if ERROR, 2 if timeout
; Clobbers: A, X, Y, zp_temp1-4
; -----------------------------------------------------------------------------
modem_send_cmd:
        ; Send "AT"
        lda #'A'
        jsr serial_send_byte
        lda #'T'
        jsr serial_send_byte

        ; Send command string
        jsr serial_send_string

        ; Send CR
        lda #$0d
        jsr serial_send_byte

        ; Wait for response
        jmp modem_wait_response

; -----------------------------------------------------------------------------
; Wait for OK or ERROR response
; Returns: A = 0 if OK, 1 if ERROR, 2 if timeout
; Clobbers: A, X, Y, zp_temp3, zp_temp4
; -----------------------------------------------------------------------------
modem_wait_response:
        ; Initialize timeout counter
        lda #0
        sta zp_temp3            ; Low byte
        sta zp_temp4            ; High byte

.resp_loop:
        ; Increment timeout counter
        inc zp_temp3
        bne .resp_no_overflow
        inc zp_temp4
        lda zp_temp4
        cmp #$30                ; Timeout threshold (~5 seconds)
        bcs .resp_timeout
.resp_no_overflow:

        ; Check for incoming data
        jsr serial_available
        bne .resp_loop          ; No data, keep waiting

        ; Read character
        jsr serial_recv_byte

        ; Check for 'O' (start of "OK")
        cmp #'O'
        beq .resp_check_ok

        ; Check for 'E' (start of "ERROR")
        cmp #'E'
        beq .resp_error

        ; Keep waiting for recognizable response
        jmp .resp_loop

.resp_check_ok:
        ; Wait for 'K' to confirm "OK"
        jsr serial_recv_byte
        cmp #'K'
        bne .resp_loop          ; False positive, keep looking
        lda #0                  ; OK response
        rts

.resp_error:
        lda #1                  ; ERROR response
        rts

.resp_timeout:
        lda #2                  ; Timeout
        rts

; -----------------------------------------------------------------------------
; Reset modem (ATZ)
; Returns: A = 0 if OK, nonzero if failed
; -----------------------------------------------------------------------------
modem_reset:
        lda #<cmd_z
        sta zp_ptr1
        lda #>cmd_z
        sta zp_ptr1+1
        jsr modem_send_cmd
        rts

cmd_z:
        !text "Z"
        !byte 0

; -----------------------------------------------------------------------------
; Dial TCP connection
; Input: zp_ptr1 = pointer to "host:port" string
; Returns: A = 0 if connected, 1 if failed
; Clobbers: A, X, Y, zp_temp1-4
; -----------------------------------------------------------------------------
modem_dial:
        ; Save IP string pointer
        lda zp_ptr1
        sta zp_temp1
        lda zp_ptr1+1
        sta zp_temp2

        ; Send "AT"
        lda #'A'
        jsr serial_send_byte
        lda #'T'
        jsr serial_send_byte

        ; Send "DT" (dial tone - works for TCP too)
        lda #'D'
        jsr serial_send_byte
        lda #'T'
        jsr serial_send_byte

        ; Send host:port
        lda zp_temp1
        sta zp_ptr1
        lda zp_temp2
        sta zp_ptr1+1
        jsr serial_send_string

        ; Send CR
        lda #$0d
        jsr serial_send_byte

        ; Wait for CONNECT or NO CARRIER
        jmp modem_wait_connect

; -----------------------------------------------------------------------------
; Wait for CONNECT response
; Returns: A = 0 if connected, 1 if failed/timeout
; Clobbers: A, X, Y, zp_temp3, zp_temp4
; -----------------------------------------------------------------------------
modem_wait_connect:
        ; Initialize timeout counter
        lda #0
        sta zp_temp3
        sta zp_temp4

.conn_loop:
        ; Increment timeout (longer for connect)
        inc zp_temp3
        bne .conn_no_overflow
        inc zp_temp4
        lda zp_temp4
        cmp #$60                ; Longer timeout for connection (~10 seconds)
        bcs .conn_timeout
.conn_no_overflow:

        ; Check for data
        jsr serial_available
        bne .conn_loop

        ; Read character
        jsr serial_recv_byte

        ; Check for 'C' (start of "CONNECT")
        cmp #'C'
        beq .conn_success

        ; Check for 'N' (start of "NO CARRIER")
        cmp #'N'
        beq .conn_failed

        jmp .conn_loop

.conn_success:
        ; Drain rest of response line
        jsr modem_drain_line
        lda #0                  ; Connected!
        rts

.conn_failed:
        lda #1                  ; Failed
        rts

.conn_timeout:
        lda #1                  ; Timeout = failed
        rts

; -----------------------------------------------------------------------------
; Drain characters until CR/LF (clear response line)
; -----------------------------------------------------------------------------
modem_drain_line:
        lda #0
        sta zp_temp3            ; Timeout counter

.dl_loop:
        inc zp_temp3
        beq .dl_done            ; Timeout after 256 chars

        jsr serial_available
        bne .dl_loop            ; No data, keep waiting

        jsr serial_recv_byte
        cmp #$0d                ; CR?
        beq .dl_done
        cmp #$0a                ; LF?
        bne .dl_loop

.dl_done:
        rts
