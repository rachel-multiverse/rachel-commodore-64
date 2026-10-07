; =============================================================================
; MAIN GAME LOOP
; =============================================================================
; Core gameplay loop - handles input, network, and display updates
;
; Online play is server-authoritative; this loop does not use the solo kernel.
; We send PLAY_CARD/DRAW_CARD actions and receive state updates.

; =============================================================================
; GAME LOOP
; =============================================================================

game_loop:
        ; Remove host-entry and lobby prompts before drawing the table.
        jsr screen_init
        jsr draw_game_screen
        ; Initial draw
        jsr redraw_game
        jsr gl_reset_watchdog
        jsr reconnect_mark_response

.gl_main:
        ; Check for network messages
        jsr check_network
        jsr gl_check_link
        jsr gl_draw_if_quiet
        jsr gl_watchdog

!if E2E_AUTOPLAY = 0 {
        ; Check for keyboard input
        jsr check_input
}
!if E2E_AUTOPLAY {
        ; Test builds take their turn from the move policy instead.
        jsr autoplay_turn
}

        ; Small delay to avoid burning CPU
        ldx #$20
-       dex
        bne -

        jmp .gl_main

; -----------------------------------------------------------------------------
; Ask for fresh authoritative state after a quiet interval. Valid replies reset
; the liveness deadline, so a player may think without triggering reconnect.
; Defer expensive redraws until the transport is quiet to avoid overflowing
; the user-port receive ring during a state/hand burst.
; -----------------------------------------------------------------------------
gl_want_redraw:
        lda #1
        sta gl_redraw_pending
        rts

gl_draw_if_quiet:
        lda gl_redraw_pending
        beq .gd_done
        jsr transport_available
        beq .gd_done            ; a frame is arriving; painting can wait
        lda #0
        sta gl_redraw_pending
        jmp redraw_game
.gd_done:
        rts

gl_redraw_pending:
        !byte 0

GL_WATCHDOG_PASSES = 2000

gl_watchdog:
        lda gl_quiet_lo
        bne .gw_tick_lo
        lda gl_quiet_hi
        beq .gw_fire
        dec gl_quiet_hi
.gw_tick_lo:
        dec gl_quiet_lo
        rts

.gw_fire:
        jsr gl_reset_watchdog
        lda SERVER_SYNC_ACK
        beq .gw_done            ; host is not gating turns; nothing to recover
        jmp rubp_send_sync_request
.gw_done:
        rts

gl_check_link:
        jsr reconnect_check_silence
        lda transport_link_down
        beq .gcl_done
        jmp reconnect_session
.gcl_done:
        rts

gl_reset_watchdog:
        lda #<GL_WATCHDOG_PASSES
        sta gl_quiet_lo
        lda #>GL_WATCHDOG_PASSES
        sta gl_quiet_hi
        rts

gl_quiet_lo:
        !byte 0
gl_quiet_hi:
        !byte 0

; -----------------------------------------------------------------------------
; Check for incoming network messages
; -----------------------------------------------------------------------------
check_network:
        jsr transport_available
        bne .cn_done            ; No data waiting

        ; Data available - receive full RUBP message
        jsr rubp_receive
        cmp #0
        bne .cn_done
        jsr rubp_validate
        bne .cn_done            ; Invalid message
        jsr gl_reset_watchdog
        jsr reconnect_mark_response

        ; Handle based on message type
        jsr rubp_get_type

        cmp #MSG_GAME_STATE
        beq .cn_game_state

        cmp #MSG_CARD_DRAWN
        beq .cn_card_drawn

        cmp #MSG_HAND_SYNC
        beq .cn_hand_sync

        cmp #MSG_TURN_START
        beq .cn_turn_start

        cmp #MSG_PLAYER_WON
        beq .cn_player_won

        cmp #MSG_ERROR
        beq .cn_error

        ; Unknown message - ignore
.cn_done:
        rts

.cn_game_state:
        jsr rubp_parse_game_state
        jmp gl_want_redraw

.cn_card_drawn:
        jsr rubp_parse_card_drawn
        jmp gl_want_redraw

.cn_hand_sync:
        jsr rubp_parse_game_start
        jsr gl_want_redraw
        ; HAND_SYNC completes the recovery pair, so this is where the host is
        ; waiting. Only answer when it negotiated the capability: an ACK flag
        ; sent to a host that did not is read as a plain resync request, and
        ; would pull the pair down again on every HAND_SYNC.
        lda SERVER_SYNC_ACK
        beq .cn_done
        jmp rubp_send_sync_ack

.cn_turn_start:
        ; Turn started - update status
        ; Current player is in payload+0
        lda SERIAL_RX_BUF+PAYLOAD_START
        sta zp_current_turn
        jsr gl_want_redraw
!if E2E_AUTOPLAY {
        ; A new turn releases exactly one autoplay action.
        lda #0
        sta AUTOPLAY_WAITING
}
        rts

.cn_player_won:
        ; Game over - show winner
        lda SERIAL_RX_BUF+PAYLOAD_START  ; Winner index
        sta WINNER_INDEX
        lda #1
        sta GAME_OVER
        jsr show_winner
        rts

.cn_error:
        ; The host rejected the action. Retrying against the same local view
        ; would be rejected the same way: the reason the action was wrong is
        ; that this client is looking at a stale table. Ask for the
        ; authoritative state instead, which is what the client guide requires
        ; of an ERROR — never retry a stale action blindly.
        jsr show_error_msg
        jsr clear_selected_cards
!if E2E_AUTOPLAY {
        ; Let the move policy try again once fresh state arrives.
        lda #0
        sta AUTOPLAY_WAITING
}
        jmp rubp_send_sync_request

; -----------------------------------------------------------------------------
; Check for keyboard input
; -----------------------------------------------------------------------------
check_input:
        jsr GETIN
        beq .ci_done            ; No key pressed

        ; Check if it's our turn
        tax                     ; preserve GETIN result while checking the turn
        lda zp_current_turn
        cmp zp_my_index
        bne .ci_not_turn        ; Not our turn

        ; It's our turn - handle the saved key.
        txa
        cmp #$1d                ; Cursor Right
        beq .ci_right
        cmp #$9d                ; Cursor Left
        beq .ci_left
        cmp #' '                ; Space = select
        beq .ci_select
        cmp #'P'                ; P = play selected
        beq .ci_play
        cmp #'p'                ; p = play selected
        beq .ci_play
        cmp #'D'                ; D = draw
        beq .ci_draw
        cmp #'d'                ; d = draw
        beq .ci_draw

.ci_not_turn:
.ci_done:
        rts

.ci_right:
        lda zp_hand_count
        beq .ci_done
        ; Move cursor right
        inc zp_cursor_pos
        lda zp_cursor_pos
        cmp zp_hand_count
        bcc .ci_update_hand
        lda #0
        sta zp_cursor_pos       ; Wrap to start
        jmp .ci_update_hand

.ci_left:
        lda zp_hand_count
        beq .ci_done
        ; Move cursor left
        dec zp_cursor_pos
        bpl .ci_update_hand
        lda zp_hand_count       ; Wrap to end
        sec
        sbc #1
        sta zp_cursor_pos
        jmp .ci_update_hand

.ci_select:
        lda zp_hand_count
        beq .ci_done
        ; Toggle selection of current card
        ldx zp_cursor_pos
        lda #1
        eor SELECTED_CARDS,x
        sta SELECTED_CARDS,x

.ci_update_hand:
        jsr draw_hand
        rts

.ci_play:
        ; Check if any cards selected
        jsr count_selected_cards
        beq .ci_done

        ; Check if playing an Ace - need to nominate suit
        jsr check_for_ace
        cmp #0
        beq .ci_send_play

        ; Ace selected - get suit nomination
        jsr get_suit_nomination
        jmp .ci_send_play_suit

.ci_send_play:
        ; Send PLAY_CARD with no suit nomination
        lda #$ff                ; No nomination
        sta zp_temp2
        jsr rubp_send_play_card

        ; Clear selection
        jsr clear_selected_cards
        jsr draw_hand
        rts

.ci_send_play_suit:
        ; zp_temp2 already has nominated suit
        jsr rubp_send_play_card

        ; Clear selection
        jsr clear_selected_cards
        jsr draw_hand
        rts

.ci_draw:
        ; Send DRAW_CARD message
        lda #0                  ; Reason: can't play
        jsr rubp_send_draw_card
        rts

; -----------------------------------------------------------------------------
; Check if any selected card is an Ace (rank 14)
; Returns: A = 0 if no ace, 1 if ace selected
; -----------------------------------------------------------------------------
check_for_ace:
        ldx #0

.cfe_loop:
        cpx zp_hand_count
        beq .cfe_none

        ; Check if this card is selected
        lda SELECTED_CARDS,x
        beq .cfe_next

        ; Selected - check if it's an Ace (rank 14)
        lda MY_HAND,x
        and #$3f                ; Get rank
        cmp #14                 ; Ace?
        beq .cfe_found

.cfe_next:
        inx
        bne .cfe_loop

.cfe_none:
        lda #0
        rts

.cfe_found:
        lda #1
        rts

count_selected_cards:
        lda #0
        sta zp_temp1
        ldx #0
.csc_loop:
        cpx zp_hand_count
        beq .csc_done
        lda SELECTED_CARDS,x
        beq .csc_next
        inc zp_temp1
.csc_next:
        inx
        bne .csc_loop
.csc_done:
        lda zp_temp1
        rts

clear_selected_cards:
        ldx #31
        lda #0
.clear_loop:
        sta SELECTED_CARDS,x
        dex
        bpl .clear_loop
        rts

; -----------------------------------------------------------------------------
; Get suit nomination from user (for Aces)
; Returns: zp_temp2 = nominated suit (0-3)
; -----------------------------------------------------------------------------
get_suit_nomination:
        ; Show prompt on status line
        ldx #1
        ldy #24
        clc
        jsr screen_goto

        lda #<txt_nominate_suit
        sta zp_ptr1
        lda #>txt_nominate_suit
        sta zp_ptr1+1
        jsr screen_print

.gsn_wait:
        jsr GETIN
        beq .gsn_wait

        ; H = Hearts
        cmp #'H'
        beq .gsn_hearts
        cmp #'h'
        beq .gsn_hearts

        ; D = Diamonds
        cmp #'D'
        beq .gsn_diamonds
        cmp #'d'
        beq .gsn_diamonds

        ; C = Clubs
        cmp #'C'
        beq .gsn_clubs
        cmp #'c'
        beq .gsn_clubs

        ; S = Spades
        cmp #'S'
        beq .gsn_spades
        cmp #'s'
        beq .gsn_spades

        jmp .gsn_wait           ; Invalid key, try again

.gsn_hearts:
        lda #0
        sta zp_temp2
        jmp .gsn_done

.gsn_diamonds:
        lda #1
        sta zp_temp2
        jmp .gsn_done

.gsn_clubs:
        lda #2
        sta zp_temp2
        jmp .gsn_done

.gsn_spades:
        lda #3
        sta zp_temp2

.gsn_done:
        ; Restore status line
        jsr draw_status
        lda zp_temp2            ; also return the suit to the solo caller
        rts

txt_nominate_suit:
        !text "NOMINATE SUIT: H D C S ?              "
        !byte 0

; -----------------------------------------------------------------------------
; Show winner screen
; -----------------------------------------------------------------------------
show_winner:
        jsr draw_result
        jsr input_wait_key
        jmp start

; PLAYER_WON's legacy WinnerIndex is the surviving player, who LOST.
; Keep rendering separate from the wait so the screen can be verified.
draw_result:
        jsr redraw_game
        ldy #12
        jsr screen_clear_row
        ldx #2
        ldy #12
        jsr screen_goto
        lda WINNER_INDEX
        cmp zp_my_index
        beq .result_last
        lda #<txt_you_out
        sta zp_ptr1
        lda #>txt_you_out
        sta zp_ptr1+1
        jmp .result_print
.result_last:
        lda #<txt_you_last
        sta zp_ptr1
        lda #>txt_you_last
        sta zp_ptr1+1
.result_print:
        jsr screen_print
        ldy #24
        jsr screen_clear_row
        ldx #1
        ldy #24
        jsr screen_goto
        lda #<txt_result_key
        sta zp_ptr1
        lda #>txt_result_key
        sta zp_ptr1+1
        jmp screen_print

txt_you_out:
        !text "GAME OVER - YOU WENT OUT"
        !byte 0
txt_you_last:
        !text "GAME OVER - YOU FINISHED LAST"
        !byte 0
txt_result_key:
        !text "PRESS A KEY FOR THE MENU"
        !byte 0

; -----------------------------------------------------------------------------
; Show error message from server
; -----------------------------------------------------------------------------
show_error_msg:
        ldx #1
        ldy #24
        clc
        jsr screen_goto

        lda #<txt_server_error
        sta zp_ptr1
        lda #>txt_server_error
        sta zp_ptr1+1
        jsr screen_print

        ; Brief delay then restore status
        jsr delay_250ms
        jsr delay_250ms
        jsr draw_status
        rts

txt_server_error:
        !text "SERVER: INVALID PLAY                  "
        !byte 0
