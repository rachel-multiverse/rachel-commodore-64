; =============================================================================
; SOLO GAME DRIVER
; =============================================================================
; Standalone play against local opponents. Permitted by decision 0006; the line
; decision 0003 still draws is that this kernel never meets the network, and the
; networked path never asks it whether a move is legal.
;
; The screen is the client's existing renderer. Rather than grow a second set of
; drawing routines, the driver publishes kernel state into the same variables
; the online path fills from GAME_STATE and HAND_SYNC, then calls redraw_game.
; One renderer, two sources for its inputs.

; -----------------------------------------------------------------------------
; Copy kernel state into the variables the renderer reads.
; Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
solo_publish:
        jsr sk_discard_top
        sta DISCARD_TOP
        lda SK_NOMINATED_SUIT
        sta NOMINATED_SUIT
        lda SK_PENDING_DRAWS
        sta PENDING_DRAWS
        lda SK_PENDING_SKIPS
        sta PENDING_SKIPS
        lda SK_DECK_COUNT
        sta DECK_COUNT
        lda SK_DIRECTION
        sta DIRECTION
        lda SK_CURRENT_PLAYER
        sta zp_current_turn
        lda #0
        sta zp_my_index         ; the human always holds seat 0

        ldx #0
.spub_counts:
        lda SK_HANDLEN,x
        sta PLAYER_COUNTS,x
        inx
        cpx #MAX_PLAYERS
        bne .spub_counts

        ; Keep the cursor inside the hand, which shrinks as cards are played.
        lda zp_cursor_pos
        cmp SK_HANDLEN
        bcc .spub_cursor_ok
        lda #0
        sta zp_cursor_pos
.spub_cursor_ok:

        ; Seat 0's hand is what the renderer shows as "your hand".
        lda SK_HANDLEN
        sta zp_hand_count
        ldy #0
.spub_hand:
        cpy zp_hand_count
        bcs .spub_done
        ldx #0
        jsr sk_hand_get
        sta MY_HAND,y
        iny
        bne .spub_hand
.spub_done:
        rts

; -----------------------------------------------------------------------------
; Play a whole standalone game. Returns when it is over.
; -----------------------------------------------------------------------------
solo_run:
        jsr solo_seed_from_machine
        jsr solo_ask_players
        jsr sk_new_game

.srun_turn:
        jsr solo_publish
        jsr redraw_game

        jsr sk_begin_turn
        cmp #SK_TURN_NEEDS_INPUT
        beq .srun_choose
        ; Skipped or drew: nothing to choose, the turn simply ends.
        jmp .srun_next

.srun_choose:
        lda SK_CURRENT_PLAYER
        beq .srun_human
        jsr solo_ai_turn
        jmp .srun_next
.srun_human:
        jsr solo_human_turn

.srun_next:
        jsr sk_end_turn
        jsr sk_game_over
        bcc .srun_turn

        jsr solo_publish
        jsr redraw_game
        jmp solo_show_result

; -----------------------------------------------------------------------------
; The opponent takes its turn.
; -----------------------------------------------------------------------------
solo_ai_turn:
        jsr sk_ai_choose
        bcc .sai_draw
        jmp sk_play_index
.sai_draw:
        jsr sk_deck_pop
        bcc .sai_dry
        ldx SK_CURRENT_PLAYER
        jmp sk_hand_add
.sai_dry:
        rts

; -----------------------------------------------------------------------------
; Seat zero's turn: move the cursor, play or draw. The kernel has already
; established that at least one legal play exists, and the mandatory play rule
; means drawing is not on offer — so an illegal choice is simply refused rather
; than accepted and then punished.
; -----------------------------------------------------------------------------
solo_human_turn:
.shum_wait:
        jsr GETIN
        beq .shum_wait

        cmp #$1d                ; cursor right
        beq .shum_right
        cmp #$9d                ; cursor left
        beq .shum_left
        cmp #'P'
        beq .shum_play
        cmp #'p'
        beq .shum_play
        bne .shum_wait

.shum_right:
        inc zp_cursor_pos
        lda zp_cursor_pos
        cmp zp_hand_count
        bcc .shum_redraw
        lda #0
        sta zp_cursor_pos
        beq .shum_redraw
.shum_left:
        dec zp_cursor_pos
        bpl .shum_redraw
        lda zp_hand_count
        sec
        sbc #1
        sta zp_cursor_pos
.shum_redraw:
        jsr draw_hand
        jmp .shum_wait

.shum_play:
        ; Refuse a card the rules do not allow, rather than sending it nowhere.
        ldy zp_cursor_pos
        ldx #0
        jsr sk_hand_get
        jsr sk_card_playable
        bcc .shum_wait

        ; An ace needs a suit, and the player names it.
        ldy zp_cursor_pos
        ldx #0
        jsr sk_hand_get
        jsr sk_card_rank
        cmp #RANK_ACE
        bne .shum_send
        jsr get_suit_nomination
        tax
        ldy zp_cursor_pos
        jmp sk_play_index
.shum_send:
        ldx #SK_NO_SUIT
        ldy zp_cursor_pos
        jmp sk_play_index
