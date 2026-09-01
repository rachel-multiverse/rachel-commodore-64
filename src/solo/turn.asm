; =============================================================================
; SOLO TURN RESOLUTION
; =============================================================================
; The order here is docs/GAME_RULES.md's turn structure, step for step: pending
; skips, then pending draws, then ordinary play. The mandatory play rule runs
; through all three — if a seat can play, it must.

SK_TURN_PLAYED   = 0            ; the seat played and the turn moves on
SK_TURN_DREW     = 1            ; the seat drew, which always ends its turn
SK_TURN_SKIPPED  = 2            ; the seat could not answer a 7
SK_TURN_NEEDS_INPUT = 3         ; a human seat has a choice to make

; -----------------------------------------------------------------------------
; Resolve everything about the current seat's turn that is not a choice.
; Out: A = SK_TURN_*, and for NEEDS_INPUT the seat has at least one legal play.
; Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
sk_begin_turn:
        lda SK_PENDING_SKIPS
        beq .trb_draws

        ; Facing 7s: counter with a 7 or lose the turn. sk_card_playable
        ; already narrows legality to sevens while a skip is live, so "has a
        ; legal play" and "holds a usable 7" are the same question.
        lda SK_CURRENT_PLAYER
        jsr sk_seat_has_play
        bcs .trb_choose
        dec SK_PENDING_SKIPS
        lda #SK_TURN_SKIPPED
        rts

.trb_draws:
        lda SK_PENDING_DRAWS
        beq .trb_normal

        ; Facing an attack: counter, or take the whole penalty at once.
        lda SK_CURRENT_PLAYER
        jsr sk_seat_has_play
        bcs .trb_choose
        jsr sk_take_penalty
        lda #SK_TURN_DREW
        rts

.trb_normal:
        lda SK_CURRENT_PLAYER
        jsr sk_seat_has_play
        bcs .trb_choose

        ; Nothing playable: draw one, and that ends the turn.
        jsr sk_deck_pop
        bcc .trb_dry
        ldx SK_CURRENT_PLAYER
        jsr sk_hand_add
.trb_dry:
        lda #SK_TURN_DREW
        rts

.trb_choose:
        lda #SK_TURN_NEEDS_INPUT
        rts

; -----------------------------------------------------------------------------
; Draw the whole pending penalty into the current seat and clear it.
; Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
sk_take_penalty:
        lda SK_PENDING_DRAWS
        beq .trp_done
        sta sk_penalty_left
.trp_loop:
        jsr sk_deck_pop
        bcc .trp_dry
        ldx SK_CURRENT_PLAYER
        jsr sk_hand_add
.trp_dry:
        dec sk_penalty_left
        bne .trp_loop
        lda #0
        sta SK_PENDING_DRAWS
.trp_done:
        rts

; -----------------------------------------------------------------------------
; Play the card at hand index Y for the current seat.
; In: Y = hand index, X = nominated suit when the card is an ace.
; Out: A = SK_TURN_PLAYED. Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
sk_play_index:
        stx sk_play_suit
        sty sk_play_slot
        ldx SK_CURRENT_PLAYER
        jsr sk_hand_get
        sta sk_play_card

        ldx SK_CURRENT_PLAYER
        ldy sk_play_slot
        jsr sk_hand_remove

        lda sk_play_card
        ldx sk_play_suit
        jsr sk_apply_card

        ; An emptied hand is out, and the seat that empties last loses.
        ldx SK_CURRENT_PLAYER
        lda SK_HANDLEN,x
        bne .tri_done
        jsr sk_seat_finished
.tri_done:
        lda #SK_TURN_PLAYED
        rts

; -----------------------------------------------------------------------------
; Hand the turn on. A skip that is still pending is spent moving past the seat
; it lands on, which is how 7s pass through and can wrap onto the player who
; threw them in a two-hand game.
; Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
sk_end_turn:
        jsr sk_bump_turn_number
        jmp sk_step_seat

; -----------------------------------------------------------------------------
; Advance the 32-bit big-endian turn counter.
; -----------------------------------------------------------------------------
sk_bump_turn_number:
        inc SK_TURN_NUMBER+3
        bne .trn_done
        inc SK_TURN_NUMBER+2
        bne .trn_done
        inc SK_TURN_NUMBER+1
        bne .trn_done
        inc SK_TURN_NUMBER
.trn_done:
        rts

sk_penalty_left: !byte 0
sk_play_slot:    !byte 0
sk_play_suit:    !byte 0
sk_play_card:    !byte 0
