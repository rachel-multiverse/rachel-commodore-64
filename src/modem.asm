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
        ; zp_ptr1 already points at HOST:PORT, and serial_send_byte leaves it
        ; alone, so there is nothing to save here. The previous version parked
        ; the pointer in zp_temp1 — the very byte serial_send_byte overwrites
        ; with each character it sends — so by the time the address was wanted
        ; the low byte had become the last character sent, and the modem was
        ; dialled with whatever bytes happened to live at that address. In this
        ; build that was the client's own machine code.
        lda #'A'
        jsr serial_send_byte
        lda #'T'
        jsr serial_send_byte

        ; "DT" - the tone/pulse distinction is meaningless over TCP, and
        ; Zimodem treats ATD, ATDT and ATDI alike.
        lda #'D'
        jsr serial_send_byte
        lda #'T'
        jsr serial_send_byte

        ; Send host:port
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
        ; The reply arrives as one burst, so hold the mask across all of it.
        sei
        ; Initialize timeout counter
        lda #0
        sta zp_temp3
        sta zp_temp4

.mwc_loop:
        ; Increment timeout (longer for connect)
        inc zp_temp3
        bne .mwc_no_overflow
        inc zp_temp4
        lda zp_temp4
        cmp #$60                ; Longer timeout for connection (~10 seconds)
        bcs .mwc_timeout
.mwc_no_overflow:

        ; Check for data
        jsr serial_available
        bne .mwc_loop

        ; Read character
        jsr serial_recv_byte

        ; Check for 'C' (start of "CONNECT")
        cmp #'C'
        beq .mwc_success

        ; Check for 'N' (start of "NO CARRIER")
        cmp #'N'
        beq .mwc_fail

        jmp .mwc_loop

.mwc_success:
        ; Drain rest of response line
        jsr modem_drain_line
        cli
        lda #0                  ; Connected!
        rts

.mwc_fail:
        cli
        lda #1                  ; Failed
        rts

.mwc_timeout:
        cli
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
