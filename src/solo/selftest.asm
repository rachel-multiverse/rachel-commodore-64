; =============================================================================
; SOLO KERNEL SELF-TEST - TEST BUILDS ONLY
; =============================================================================
; Plays complete games from fixed seeds with every seat driven by the kernel's
; own policy, and checks two things after each one:
;
;   - the game actually ended, rather than running out the turn bound
;   - all 52 cards are still accounted for
;
; The card count is the invariant that catches the whole family of bugs a card
; kernel is prone to: a draw that does not remove from the deck, a play that
; does not remove from a hand, a recycle that duplicates the pile. A game can
; look perfectly plausible on screen while quietly minting cards.
;
; Results are left in memory for the host harness to read back.

SOLO_TEST_GAMES  = 16
SOLO_TURN_BOUND  = 1024

solo_test_run:
        lda #0
        sta solo_test_passed
        sta solo_test_failed
        sta solo_test_bounded
        sta solo_test_game

.stt_game:
        ; A distinct seed per game, and a seat count that walks 2-8 so every
        ; deal size in the rules gets exercised.
        ldx solo_test_game
        lda solo_test_seeds,x
        sta SK_RANDOM_SEED
        lda #0
        sta SK_RANDOM_SEED+1
        sta SK_RANDOM_SEED+2
        sta SK_RANDOM_SEED+3
        sta SK_RANDOM_SEED+4
        sta SK_RANDOM_SEED+5
        sta SK_RANDOM_SEED+6
        sta SK_RANDOM_SEED+7

        lda solo_test_game
        and #7
        clc
        adc #2
        cmp #9
        bcc .stt_seats
        lda #8
.stt_seats:
        jsr sk_new_game

        lda #<SOLO_TURN_BOUND
        sta solo_test_turns
        lda #>SOLO_TURN_BOUND
        sta solo_test_turns+1

.stt_turn:
        jsr sk_begin_turn
        cmp #SK_TURN_NEEDS_INPUT
        bne .stt_advance
        jsr sk_ai_choose
        bcc .stt_draw
        jsr sk_play_index
        jmp .stt_advance
.stt_draw:
        jsr sk_deck_pop
        bcc .stt_dry
        ldx SK_CURRENT_PLAYER
        jsr sk_hand_add
.stt_dry:

.stt_advance:
        jsr sk_end_turn
        jsr sk_game_over
        bcs .stt_ended

        ; Bounded so a rules bug that stalls the table fails loudly rather
        ; than hanging the harness.
        lda solo_test_turns
        bne .stt_dec_lo
        lda solo_test_turns+1
        beq .stt_bound_hit
        dec solo_test_turns+1
.stt_dec_lo:
        dec solo_test_turns
        jmp .stt_turn

.stt_bound_hit:
        inc solo_test_bounded
        jmp .stt_next

.stt_ended:
        jsr solo_test_count_cards
        cmp #52
        beq .stt_pass
        sta solo_test_last_count    ; below 52 is loss, above is duplication
        inc solo_test_failed
        jmp .stt_next
.stt_pass:
        inc solo_test_passed

.stt_next:
        inc solo_test_game
        lda solo_test_game
        cmp #SOLO_TEST_GAMES
        bcs .stt_all_done
        jmp .stt_game           ; trampoline: the game body is a long branch away
.stt_all_done:
        rts

; -----------------------------------------------------------------------------
; Every card should be in exactly one of: the deck, the discard pile, or a hand.
; Out: A = total. Clobbers: A, X.
; -----------------------------------------------------------------------------
solo_test_count_cards:
        lda SK_DECK_COUNT
        clc
        adc SK_DISCARD_COUNT
        ldx #0
.stc_seats:
        clc
        adc SK_HANDLEN,x
        inx
        cpx #SK_MAX_PLAYERS
        bne .stc_seats
        rts

solo_test_seeds:
        !byte 1, 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47

solo_test_passed:  !byte 0
solo_test_failed:  !byte 0
solo_test_bounded: !byte 0
solo_test_game:    !byte 0
solo_test_turns:   !byte 0, 0
solo_test_last_count: !byte 0
