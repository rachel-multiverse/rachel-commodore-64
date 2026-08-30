; =============================================================================
; CONNECT MODULE
; =============================================================================
; Handles connection flow: IP input -> dial -> handshake -> wait for game
;
; Connection state machine (values defined in zeropage.asm):
;   CONN_DISCONNECTED (0) - Initial state
;   CONN_DIALING (1)      - Sent ATDT, waiting CONNECT
;   CONN_HANDSHAKE (2)    - Connected, sending HELLO
;   CONN_WAITING (3)      - Got WELCOME, waiting for GAME_START
;   CONN_PLAYING (4)      - In game

; =============================================================================
; CONNECTION SUBROUTINES
; =============================================================================

; -----------------------------------------------------------------------------
; Input IP address from user
; Stores result in IP_INPUT_BUF (null-terminated)
; Returns: A = length of input (0 if cancelled)
; -----------------------------------------------------------------------------
input_ip_address:
        ; Position cursor on input line
        ldx #1
        ldy #22
        clc
        jsr PLOT

        ; Show prompt
        lda #<txt_ip_prompt
        sta zp_ptr1
        lda #>txt_ip_prompt
        sta zp_ptr1+1
        jsr screen_print

        ; Initialize input buffer
        lda #0
        sta zp_temp1            ; Current length
        ldx #0
-       sta IP_INPUT_BUF,x      ; Clear buffer
        inx
        cpx #32
        bne -

        ; Show cursor
        lda #$A0                ; Reverse space (cursor)
        jsr CHROUT

.input_loop:
        jsr GETIN
        beq .input_loop         ; No key, keep waiting

        ; Check for RETURN
        cmp #$0d
        beq .input_done

        ; Check for backspace/DEL
        cmp #$14                ; DEL key
        beq .input_backspace

        ; Check for printable char
        cmp #$20
        bcc .input_loop         ; Ignore control chars
        cmp #$7f
        bcs .input_loop         ; Ignore high chars

        ; Check buffer full
        ldx zp_temp1
        cpx #30                 ; Max 30 chars
        bcs .input_loop

        ; Store character
        sta IP_INPUT_BUF,x
        inc zp_temp1

        ; Display character (overwrite cursor)
        ; First move cursor back
        lda #$9d                ; Cursor left
        jsr CHROUT
        ; Print the character
        ldx zp_temp1
        dex
        lda IP_INPUT_BUF,x
        jsr CHROUT
        ; Print new cursor
        lda #$A0
        jsr CHROUT
        jmp .input_loop

.input_backspace:
        ldx zp_temp1
        beq .input_loop         ; Nothing to delete

        dec zp_temp1

        ; Erase cursor, move back, erase char, show cursor
        lda #$9d                ; Left
        jsr CHROUT
        lda #' '                ; Erase cursor
        jsr CHROUT
        lda #$9d                ; Left
        jsr CHROUT
        lda #$9d                ; Left again
        jsr CHROUT
        lda #$A0                ; New cursor position
        jsr CHROUT
        jmp .input_loop

.input_done:
        ; Null-terminate
        ldx zp_temp1
        lda #0
        sta IP_INPUT_BUF,x

        ; Erase cursor
        lda #$9d
        jsr CHROUT
        lda #' '
        jsr CHROUT

        ; Return length
        lda zp_temp1
        rts

txt_ip_prompt:
        !text "HOST:PORT> "
        !byte 0

; -----------------------------------------------------------------------------
; Perform full connection sequence
; Returns: A = 0 if connected, 1 if failed
; -----------------------------------------------------------------------------
do_connect:
        ; Show connecting status
        jsr show_status_connecting

        ; Connect using the detected transport. Ultimate hardware opens a UCI
        ; TCP socket directly; the fallback resets and dials the modem.
        lda #<IP_INPUT_BUF
        sta zp_ptr1
        lda #>IP_INPUT_BUF
        sta zp_ptr1+1
        jsr transport_connect
        cmp #0
        bne .connect_fail

        ; Update state
        lda #CONN_HANDSHAKE
        sta zp_conn_state

        ; Show handshake status
        jsr show_status_handshake

        ; Send HELLO message
        lda #<player_name
        sta zp_ptr1
        lda #>player_name
        sta zp_ptr1+1
        jsr rubp_send_hello

        ; Wait for WELCOME
        jsr rubp_receive
        cmp #0
        bne .connect_fail
        jsr rubp_validate
        bne .connect_fail       ; Invalid message

        jsr rubp_get_type
        cmp #MSG_WELCOME
        bne .connect_fail       ; Not WELCOME

        ; Parse WELCOME
        jsr rubp_parse_welcome

        ; Assigned player IDs are the canonical seat indices (0-7).
        lda zp_player_id
        sta zp_my_index

        ; Update state
        lda #CONN_WAITING
        sta zp_conn_state

        ; Show waiting for game status
        jsr show_status_waiting_game

        ; Success
        lda #0
        rts

.connect_fail:
        jsr show_status_failed
        lda #1
        rts

player_name:
        !text "C64 PLAYER"
        !byte 0

; -----------------------------------------------------------------------------
; Wait for GAME_START message
; Returns: A = 0 when game starts
; -----------------------------------------------------------------------------
wait_for_game:
.wfg_loop:
        ; Check for keypress (ESC to cancel)
        jsr GETIN
        cmp #$03                ; RUN/STOP key
        beq .wfg_cancel

        ; Try to receive message (non-blocking would be better but we'll poll)
        jsr transport_available
        bne .wfg_loop           ; No data

        ; Got data - receive full message
        jsr rubp_receive
        cmp #0
        bne .wfg_cancel
        jsr rubp_validate
        bne .wfg_loop           ; Invalid, keep waiting

        ; Check message type
        jsr rubp_get_type

        ; GAME_START?
        cmp #MSG_GAME_START
        beq .wfg_game_start

        ; GAME_STATE? (also valid to start)
        cmp #MSG_GAME_STATE
        beq .wfg_game_state

        ; Keep waiting for other message types
        jmp .wfg_loop

.wfg_game_start:
        ; Parse initial hand
        jsr rubp_parse_game_start

        ; Update state
        lda #CONN_PLAYING
        sta zp_conn_state

        lda #0
        rts

.wfg_game_state:
        ; Parse game state
        jsr rubp_parse_game_state

        ; Update state
        lda #CONN_PLAYING
        sta zp_conn_state

        lda #0
        rts

.wfg_cancel:
        lda #1
        rts

; -----------------------------------------------------------------------------
; Status display helpers
; -----------------------------------------------------------------------------
show_status_connecting:
        ldx #1
        ldy #24
        clc
        jsr PLOT
        lda #<txt_status_connecting
        sta zp_ptr1
        lda #>txt_status_connecting
        sta zp_ptr1+1
        jmp screen_print

show_status_handshake:
        ldx #1
        ldy #24
        clc
        jsr PLOT
        lda #<txt_status_handshake
        sta zp_ptr1
        lda #>txt_status_handshake
        sta zp_ptr1+1
        jmp screen_print

show_status_waiting_game:
        ldx #1
        ldy #24
        clc
        jsr PLOT
        lda #<txt_status_waiting_game
        sta zp_ptr1
        lda #>txt_status_waiting_game
        sta zp_ptr1+1
        jmp screen_print

show_status_failed:
        ldx #1
        ldy #24
        clc
        jsr PLOT
        lda #<txt_status_failed
        sta zp_ptr1
        lda #>txt_status_failed
        sta zp_ptr1+1
        jmp screen_print

txt_status_connecting:
        !text "DIALING...                            "
        !byte 0

txt_status_handshake:
        !text "CONNECTED - HANDSHAKING...            "
        !byte 0

txt_status_waiting_game:
        !text "WAITING FOR GAME TO START...          "
        !byte 0

txt_status_failed:
        !text "CONNECTION FAILED - PRESS KEY         "
        !byte 0

; -----------------------------------------------------------------------------
; Simple delay (approximately 250ms)
; -----------------------------------------------------------------------------
delay_250ms:
        ldx #0
        ldy #0
-       dey
        bne -
        dex
        bne -
        rts
