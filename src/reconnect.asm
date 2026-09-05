; Reclaim a running session. Token and address survive retries, not a reset.
; Timings provide a best-effort vintage session identifier, not a CSPRNG.
reconnect_new_session:
        jsr solo_seed_from_machine
        jsr sk_seed_normalize
        jsr sk_rng_next
        ldx #7
.rn_copy:
        lda SK_RANDOM_SEED,x
        eor $dc04
        eor $d012
        sta RECONNECT_TOKEN,x
        dex
        bpl .rn_copy
        lda #1
        ora RECONNECT_TOKEN
        sta RECONNECT_TOKEN
        lda #0
        sta zp_game_id
        sta zp_game_id+1
        rts

reconnect_mark_response:
        php
        sei                     ; read one coherent jiffy count across rollover
        lda $a2
        sta rc_last_tick
        lda $a1
        sta rc_last_tick+1
        plp
        rts

; A silent socket is also a lost connection. Normal watchdog sync replies keep
; refreshing this deadline even while a human is thinking. About 10 seconds, before the server
; hands a disconnected seat to AI after its 30-second grace period.
reconnect_check_silence:
        php
        sei
        lda $a2
        sec
        sbc rc_last_tick
        tax
        lda $a1
        sbc rc_last_tick+1
        plp
        cmp #2
        bcc .rs_done
        bne .rs_lost
        cpx #88
        bcc .rs_done
.rs_lost:
        lda #1
        sta transport_link_down
.rs_done:
        rts

reconnect_session:
        lda #3
        sta rc_tries
.rc_attempt:
        jsr rc_show_reconnecting
        jsr reconnect_attempt
        beq .rc_restored
        dec rc_tries
        beq .rc_prompt
        jsr delay_250ms
        jmp .rc_attempt
.rc_prompt:
        ldy #24
        jsr screen_clear_row
        ldx #1
        ldy #24
        lda #<rc_failed_text
        sta zp_ptr1
        lda #>rc_failed_text
        sta zp_ptr1+1
        jsr screen_print_at
.rc_key:
        jsr GETIN
        cmp #'R'
        beq reconnect_session
        cmp #'r'
        beq reconnect_session
        cmp #'Q'
        beq .rc_quit
        cmp #'q'
        bne .rc_key
.rc_quit:
        lda zp_transport
        beq .rc_menu
        jsr ultimate_close
.rc_menu:
        jmp start
.rc_restored:
        jsr reconnect_mark_response
        jsr gl_reset_watchdog
        lda #0
        sta gl_redraw_pending
        jsr redraw_game
        lda GAME_OVER
        beq .rc_done
        jmp show_winner
.rc_done:
        rts

rc_show_reconnecting:
        ldy #24
        jsr screen_clear_row
        ldx #1
        ldy #24
        lda #<rc_wait_text
        sta zp_ptr1
        lda #>rc_wait_text
        sta zp_ptr1+1
        jmp screen_print_at

; Returns zero only after WELCOME + GAME_STATE + HAND_SYNC for this game.
; Never falls back to joining a new lobby with the old token.
reconnect_attempt:
        lda zp_transport
        beq .ra_modem
        jsr ultimate_close
        jmp .ra_reset
.ra_modem:
        ; Escape Hayes data mode with guard time before issuing ATZ on redial.
        jsr delay_250ms
        jsr delay_250ms
        jsr delay_250ms
        jsr delay_250ms
        lda #'+'
        jsr serial_send_byte
        lda #'+'
        jsr serial_send_byte
        lda #'+'
        jsr serial_send_byte
        jsr delay_250ms
        jsr delay_250ms
        jsr delay_250ms
        jsr delay_250ms
        ; If NO CARRIER already put the modem in command mode, +++ is an
        ; unfinished command. Terminate/drain it before ATZ rather than
        ; accidentally sending +++ATZ as one invalid command.
        lda #$0d
        jsr serial_send_byte
        jsr delay_250ms
.ra_reset:
        lda #0
        sta transport_link_down
        sta zp_rx_head
        sta HASH_VALID
        sta GAME_STATE_FRESH
        sta rc_stage
        jsr clear_selected_cards
        lda #0
        sta zp_cursor_pos
        lda zp_transport
        bne .ra_open
        jsr serial_rx_init
.ra_open:
        lda #<IP_INPUT_BUF
        sta zp_ptr1
        lda #>IP_INPUT_BUF
        sta zp_ptr1+1
        jsr transport_connect
        bne .ra_fail
        lda #<player_name
        sta zp_ptr1
        lda #>player_name
        sta zp_ptr1+1
        jsr rubp_send_hello
        lda #48
        sta rc_budget
.ra_receive:
        jsr rubp_receive
        bne .ra_next
        jsr rubp_validate
        bne .ra_next
        lda SERIAL_RX_BUF+HDR_GAME_ID
        cmp zp_game_id+1
        bne .ra_next
        lda SERIAL_RX_BUF+HDR_GAME_ID+1
        cmp zp_game_id
        bne .ra_next
        jsr rubp_get_type
        cmp #MSG_ERROR
        beq .ra_fail
        cmp #MSG_WELCOME
        beq .ra_welcome
        ldx rc_stage
        beq .ra_next
        cmp #MSG_GAME_STATE
        beq .ra_state
        cmp #MSG_HAND_SYNC
        beq .ra_hand
.ra_next:
        lda transport_link_down
        bne .ra_fail
        dec rc_budget
        bne .ra_receive
.ra_fail:
        lda #1
        rts
.ra_welcome:
        lda SERIAL_RX_BUF+PAYLOAD_START
        cmp zp_player_id+1
        bne .ra_fail
        lda SERIAL_RX_BUF+PAYLOAD_START+1
        cmp zp_player_id
        bne .ra_fail
        lda SERIAL_RX_BUF+PAYLOAD_START+2
        cmp zp_game_id+1
        bne .ra_fail
        lda SERIAL_RX_BUF+PAYLOAD_START+3
        cmp zp_game_id
        bne .ra_fail
        lda SERIAL_RX_BUF+PAYLOAD_START+8
        and #CAP_SYNC_ACK
        sta SERVER_SYNC_ACK
        lda #1
        sta rc_stage
        bne .ra_next
.ra_state:
        jsr rubp_parse_game_state
        lda #2
        sta rc_stage
        bne .ra_next
.ra_hand:
        cpx #2
        bne .ra_next
        jsr rubp_parse_game_start
        lda SERVER_SYNC_ACK
        beq .ra_ready
        jsr rubp_send_sync_request
.ra_ready:
!if E2E_AUTOPLAY {
        lda #1
        sta AUTOPLAY_WAITING
}
        lda #0
        rts

rc_tries: !byte 0
rc_stage: !byte 0
rc_budget: !byte 0
rc_last_tick: !byte 0,0
rc_wait_text: !text "CONNECTION LOST - RECONNECTING..."
        !byte 0
rc_failed_text: !text "COULD NOT RECONNECT. R RETRY  Q MENU"
        !byte 0
