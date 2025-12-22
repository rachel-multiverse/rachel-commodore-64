; =============================================================================
; MAIN GAME LOOP
; =============================================================================
; Core gameplay loop - handles input, network, and display updates
;
; This is a render-only client: all game logic is on the iOS host.
; We send PLAY_CARD/DRAW_CARD actions and receive state updates.

; =============================================================================
; GAME LOOP
; =============================================================================

game_loop:
        ; Initial draw
        jsr redraw_game

.gl_main:
        ; Check for network messages
        jsr check_network

        ; Check for keyboard input
        jsr check_input

        ; Small delay to avoid burning CPU
        ldx #$20
-       dex
        bne -

        jmp .gl_main

; -----------------------------------------------------------------------------
; Check for incoming network messages
; -----------------------------------------------------------------------------
check_network:
        jsr serial_available
        bne .cn_done            ; No data waiting

        ; Data available - receive full RUBP message
        jsr rubp_receive
        jsr rubp_validate
        bne .cn_done            ; Invalid message

        ; Handle based on message type
        jsr rubp_get_type

        cmp #MSG_GAME_STATE
        beq .cn_game_state

        cmp #MSG_CARD_DRAWN
        beq .cn_card_drawn

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
        jsr redraw_game
        rts

.cn_card_drawn:
        jsr rubp_parse_card_drawn
        jsr draw_hand
        rts

.cn_turn_start:
        ; Turn started - update status
        ; Current player is in payload+0
        lda SERIAL_RX_BUF+PAYLOAD_START
        sta zp_current_turn
        jsr draw_status
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
        ; Display error message and continue
        jsr show_error_msg
        rts

; -----------------------------------------------------------------------------
; Check for keyboard input
; -----------------------------------------------------------------------------
check_input:
        jsr GETIN
        beq .ci_done            ; No key pressed

        ; Check if it's our turn
        lda zp_current_turn
        cmp zp_my_index
        bne .ci_not_turn        ; Not our turn

        ; It's our turn - handle input
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
        ; Move cursor right
        inc zp_cursor_pos
        lda zp_cursor_pos
        cmp zp_hand_count
        bcc .ci_update_hand
        lda #0
        sta zp_cursor_pos       ; Wrap to start
        jmp .ci_update_hand

.ci_left:
        ; Move cursor left
        dec zp_cursor_pos
        bpl .ci_update_hand
        lda zp_hand_count       ; Wrap to end
        sec
        sbc #1
        sta zp_cursor_pos
        jmp .ci_update_hand

.ci_select:
        ; Toggle selection of current card
        ldx zp_cursor_pos
        cpx #8                  ; Only support first 8 cards for selection
        bcs .ci_update_hand

        ; Create bit mask for position
        lda #1
-       dex
        bmi .ci_toggle
        asl
        bne -

.ci_toggle:
        eor zp_selected_lo      ; Toggle bit
        sta zp_selected_lo

.ci_update_hand:
        jsr draw_hand
        rts

.ci_play:
        ; Check if any cards selected
        lda zp_selected_lo
        beq .ci_done            ; Nothing selected

        ; Check if playing 8 - need to nominate suit
        jsr check_for_eight
        cmp #0
        beq .ci_send_play

        ; 8 selected - get suit nomination
        jsr get_suit_nomination
        jmp .ci_send_play_suit

.ci_send_play:
        ; Send PLAY_CARD with no suit nomination
        lda #$ff                ; No nomination
        sta zp_temp2
        jsr rubp_send_play_card

        ; Clear selection
        lda #0
        sta zp_selected_lo
        sta zp_selected_hi
        jsr draw_hand
        rts

.ci_send_play_suit:
        ; zp_temp2 already has nominated suit
        jsr rubp_send_play_card

        ; Clear selection
        lda #0
        sta zp_selected_lo
        sta zp_selected_hi
        jsr draw_hand
        rts

.ci_draw:
        ; Send DRAW_CARD message
        lda #0                  ; Reason: can't play
        jsr rubp_send_draw_card
        rts

; -----------------------------------------------------------------------------
; Check if any selected card is an 8 (Ace in our encoding = 14)
; Returns: A = 0 if no ace, 1 if ace selected
; -----------------------------------------------------------------------------
check_for_eight:
        ldx #0
        lda #1                  ; Bit mask
        sta zp_temp1

.cfe_loop:
        cpx zp_hand_count
        beq .cfe_none

        ; Check if this card is selected
        lda zp_temp1
        and zp_selected_lo
        beq .cfe_next

        ; Selected - check if it's an Ace (rank 14)
        lda MY_HAND,x
        and #$3f                ; Get rank
        cmp #14                 ; Ace?
        beq .cfe_found

.cfe_next:
        asl zp_temp1
        inx
        cpx #8
        bne .cfe_loop

.cfe_none:
        lda #0
        rts

.cfe_found:
        lda #1
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
        jsr PLOT

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
        rts

txt_nominate_suit:
        !text "NOMINATE SUIT: H D C S ?              "
        !byte 0

; -----------------------------------------------------------------------------
; Show winner screen
; -----------------------------------------------------------------------------
show_winner:
        ldx #10
        ldy #12
        clc
        jsr PLOT

        ; Check if we won
        lda WINNER_INDEX
        cmp zp_my_index
        beq .sw_we_won

        ; Someone else won
        lda #<txt_you_lose
        sta zp_ptr1
        lda #>txt_you_lose
        sta zp_ptr1+1
        jsr screen_print

        ; Print winner number
        lda WINNER_INDEX
        clc
        adc #'1'
        jsr CHROUT
        jmp .sw_wait

.sw_we_won:
        lda #<txt_you_win
        sta zp_ptr1
        lda #>txt_you_win
        sta zp_ptr1+1
        jsr screen_print

.sw_wait:
        ; Wait for keypress then restart
        jsr input_wait_key
        jmp start               ; Restart game

txt_you_win:
        !text "*** YOU WIN! ***"
        !byte 0

txt_you_lose:
        !text "GAME OVER - PLAYER "
        !byte 0

; -----------------------------------------------------------------------------
; Show error message from server
; -----------------------------------------------------------------------------
show_error_msg:
        ldx #1
        ldy #24
        clc
        jsr PLOT

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
