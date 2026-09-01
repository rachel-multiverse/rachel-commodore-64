; =============================================================================
; AUTOPLAY - TEST BUILDS ONLY
; =============================================================================
; A deterministic move policy that drives the ordinary action encoders through
; a complete server-authoritative game, so the end-to-end harness can play the
; real client against the real server with no human at the keyboard.
;
; This is not an AI and it is not a rules engine. It picks a legal-looking move
; and lets the host rule on it; the host remains authoritative, exactly as it
; is for a human player (decision 0003). Production builds contain none of this
; code — the whole file sits inside `!if E2E_AUTOPLAY`.
;
; It deliberately plays one card at a time. Stacking is legal but multiplies
; the ways a test can diverge from the host without telling us anything new
; about the transport, which is what this harness exists to exercise.

; -----------------------------------------------------------------------------
; Take our turn, at most once per TURN_START.
; -----------------------------------------------------------------------------
autoplay_turn:
        lda zp_current_turn
        cmp zp_my_index
        beq .ap_our_turn
        rts

.ap_our_turn:
        ; One action per turn. TURN_START clears this, so a slow reply cannot
        ; stack up duplicate actions while the host is still thinking.
        lda AUTOPLAY_WAITING
        beq .ap_ready
        rts

.ap_ready:
        lda #1
        sta AUTOPLAY_WAITING

        ; A live attack can only be answered by the rank already on the discard:
        ; 2s counter 2s, 7s counter 7s, and a jack answers a jack (a red one
        ; blunts the black jack's five). Anything else is a draw.
        lda PENDING_DRAWS
        ora PENDING_SKIPS
        beq .ap_normal

        lda DISCARD_TOP
        and #$3f
        sta zp_temp3
        ldx #0
.ap_counter_scan:
        cpx zp_hand_count
        bcs .ap_draw
        lda MY_HAND,x
        and #$3f
        cmp zp_temp3
        beq .ap_play
        inx
        bne .ap_counter_scan
        beq .ap_draw

; -----------------------------------------------------------------------------
; No attack pending: play the first card that follows the discard.
; -----------------------------------------------------------------------------
.ap_normal:
        ldx #0
.ap_scan:
        cpx zp_hand_count
        bcs .ap_draw

        lda MY_HAND,x
        and #$3f
        cmp #14                 ; An ace plays on anything and names a suit.
        beq .ap_play_ace
        sta zp_temp3            ; this card's rank

        ; A live nomination replaces the discard's own suit as the thing to
        ; follow, so it is checked first and rank matching does not apply.
        lda NOMINATED_SUIT
        cmp #$ff
        bne .ap_match_nomination

        lda DISCARD_TOP
        and #$3f
        cmp zp_temp3
        beq .ap_play

        lda MY_HAND,x
        jsr autoplay_card_suit
        sta zp_temp3
        lda DISCARD_TOP
        jsr autoplay_card_suit
        cmp zp_temp3
        beq .ap_play
        inx
        bne .ap_scan
        beq .ap_draw

.ap_match_nomination:
        sta zp_temp3            ; the nominated suit
        lda MY_HAND,x
        jsr autoplay_card_suit
        cmp zp_temp3
        beq .ap_play
        inx
        bne .ap_scan
        beq .ap_draw

; -----------------------------------------------------------------------------
; Play the card at X, with no suit nomination.
; -----------------------------------------------------------------------------
.ap_play:
        lda #$ff                ; no nomination
        sta zp_temp2
        jmp autoplay_send_card

; -----------------------------------------------------------------------------
; Play the ace at X, naming its own suit. Any suit is legal, and naming the one
; we just played keeps the choice deterministic without having to weigh the
; hand — a policy that only has to be legal, not clever.
; -----------------------------------------------------------------------------
.ap_play_ace:
        lda MY_HAND,x
        jsr autoplay_card_suit
        sta zp_temp2
        ; fall through

; -----------------------------------------------------------------------------
; Send the card at X with the nomination already in zp_temp2. clear_selected_cards
; walks X down to -1, so the index is parked in zp_temp4 across the call.
; -----------------------------------------------------------------------------
autoplay_send_card:
        stx zp_temp4
        jsr clear_selected_cards
        ldx zp_temp4
        lda #1
        sta SELECTED_CARDS,x
        jsr rubp_send_play_card
        jmp clear_selected_cards

; -----------------------------------------------------------------------------
; Nothing to play: draw, which ends the turn.
; -----------------------------------------------------------------------------
.ap_draw:
        lda #$00                ; reason = CANNOT_PLAY
        jmp rubp_send_draw_card

; -----------------------------------------------------------------------------
; A = card -> A = suit index 0-3 (the top two bits of the encoded card).
; Preserves X.
; -----------------------------------------------------------------------------
autoplay_card_suit:
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        rts
