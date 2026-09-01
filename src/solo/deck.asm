; =============================================================================
; SOLO DECK, DEAL AND DRAW
; =============================================================================
; The shuffle is the VIC-20 kernel's, move for move: ordinals 0-51 laid out in
; order, then Fisher-Yates from the top down, consuming one xorshift64 output
; per swap. Same seed, same deal, either machine.

; -----------------------------------------------------------------------------
; A = ordinal 0-51 -> A = encoded card. suit = ordinal / 13, rank = ordinal % 13
; + 2, which is the inverse of the client's card encoding.
;
; Counts the suit in Y, not X: its only caller walks the deck with X, and an
; index quietly reset to the suit on every card is an endless loop.
; Preserves X, clobbers Y.
; -----------------------------------------------------------------------------
sk_ordinal_to_card:
        ldy #0                  ; suit
.dko_reduce:
        cmp #13
        bcc .dko_done
        sec
        sbc #13
        iny
        bne .dko_reduce
.dko_done:
        clc
        adc #2                  ; rank 2-14
        sta sk_card_temp
        tya
        asl
        asl
        asl
        asl
        asl
        asl                     ; suit into the top two bits
        ora sk_card_temp
        rts

; -----------------------------------------------------------------------------
; Start a fresh deterministic game.
; In:  A = seat count (2-8); SK_RANDOM_SEED already holds the eight-byte seed
;      (all zero selects the same fallback the VIC-20 uses).
; Out: dealt hands, one card face up, seat 0 to play.
; -----------------------------------------------------------------------------
sk_new_game:
        sta sk_new_players

        ; Clear the scalars but keep the seed the caller just set.
        ldx #7
.dkn_save_seed:
        lda SK_RANDOM_SEED,x
        sta SK_SCRATCH,x
        dex
        bpl .dkn_save_seed
        lda #0
        ldx #0
.dkn_clear:
        sta SK_STATE,x
        inx
        cpx #SK_STATE_SIZE
        bne .dkn_clear
        ldx #7
.dkn_restore_seed:
        lda SK_SCRATCH,x
        sta SK_RANDOM_SEED,x
        dex
        bpl .dkn_restore_seed

        ; The hand lengths live outside SK_STATE, so clearing the state block
        ; alone leaves the previous game's hands standing and the new deal
        ; piles on top of them. Nothing on screen looks wrong; the deck just
        ; quietly runs short.
        lda #0                  ; the seed restore above left a seed byte in A
        ldx #SK_MAX_PLAYERS-1
.dkn_clear_hands:
        sta SK_HANDLEN,x
        dex
        bpl .dkn_clear_hands

        lda sk_new_players
        sta SK_PLAYER_COUNT
        lda #SK_NO_SUIT
        sta SK_NOMINATED_SUIT
        jsr sk_seed_normalize

        ; A full deck in ordinal order, ready to be shuffled.
        ldx #0
.dkn_fill:
        txa
        jsr sk_ordinal_to_card
        sta SK_DECK,x
        inx
        cpx #52
        bne .dkn_fill
        lda #52
        sta SK_DECK_COUNT

        ; Fisher-Yates from the top down, one PRNG draw per swap.
        lda #51
        sta sk_shuffle_index
.dkn_shuffle:
        jsr sk_rng_next
        lda sk_shuffle_index
        clc
        adc #1
        jsr sk_rng_mod          ; 0 .. shuffle_index
        tay
        ldx sk_shuffle_index
        lda SK_DECK,x
        pha
        lda SK_DECK,y
        sta SK_DECK,x
        pla
        sta SK_DECK,y
        dec sk_shuffle_index
        bne .dkn_shuffle

        ; Deal round by round. Hands shrink as the table fills so eight seats
        ; still come out of one deck (docs/GAME_RULES.md).
        ldx SK_PLAYER_COUNT
        lda sk_deal_sizes-2,x
        sta sk_deal_size

        lda #0
        sta SK_CURRENT_PLAYER
.dkn_seat:
        lda sk_deal_size
        sta sk_deal_remaining
.dkn_card:
        jsr sk_deck_pop
        ldx SK_CURRENT_PLAYER
        jsr sk_hand_add         ; a fresh deck always has enough to deal
        dec sk_deal_remaining
        bne .dkn_card
        inc SK_CURRENT_PLAYER
        lda SK_CURRENT_PLAYER
        cmp SK_PLAYER_COUNT
        bcc .dkn_seat

        ; One card face up. A special starting card has no effect
        ; (docs/GAME_RULES.md), so nothing is applied here.
        jsr sk_deck_pop
        sta SK_DISCARD
        lda #1
        sta SK_DISCARD_COUNT
        lda #0
        sta SK_CURRENT_PLAYER
        rts

; Cards dealt per seat, indexed from two seats up.
sk_deal_sizes:
        !byte 7, 7, 7, 7, 6, 6, 5

; -----------------------------------------------------------------------------
; Take the next card off the deck -> A, recycling the discard pile when it runs
; out. C set when a card was drawn, clear when every card is already in a hand
; and there is genuinely nothing to draw.
; -----------------------------------------------------------------------------
sk_deck_pop:
        lda SK_DECK_COUNT
        bne .dkp_have
        jsr sk_recycle_discards
        lda SK_DECK_COUNT
        bne .dkp_have
        clc                     ; nothing left anywhere: do not invent a card
        rts
.dkp_have:
        lda SK_DECK             ; front of the deck, as the VIC-20 pops it
        pha
        ldx #0
.dkp_shift:
        lda SK_DECK+1,x
        sta SK_DECK,x
        inx
        cpx SK_DECK_COUNT
        bcc .dkp_shift
        dec SK_DECK_COUNT
        pla
        sec                     ; a card was drawn
        rts

; -----------------------------------------------------------------------------
; Turn the discard pile back into a deck, leaving the top card face up
; (docs/GAME_RULES.md). The pile is reshuffled with the live PRNG so the
; recycled order stays deterministic for a given seed.
; -----------------------------------------------------------------------------
sk_recycle_discards:
        lda SK_DISCARD_COUNT
        cmp #2
        bcc .dkr_done            ; only the face-up card: nothing to recycle

        ; Everything below the top card becomes the new deck.
        ldx SK_DISCARD_COUNT
        dex
        stx SK_DECK_COUNT
        ldx #0
.dkr_copy:
        lda SK_DISCARD,x
        sta SK_DECK,x
        inx
        cpx SK_DECK_COUNT
        bcc .dkr_copy

        ; The face-up card stays, and it is now the whole pile.
        ldx SK_DISCARD_COUNT
        dex
        lda SK_DISCARD,x
        sta SK_DISCARD
        lda #1
        sta SK_DISCARD_COUNT

        ; Shuffle the recovered cards the same way the deck was made.
        ldx SK_DECK_COUNT
        dex
        stx sk_shuffle_index
        beq .dkr_done
.dkr_shuffle:
        jsr sk_rng_next
        lda sk_shuffle_index
        clc
        adc #1
        jsr sk_rng_mod
        tay
        ldx sk_shuffle_index
        lda SK_DECK,x
        pha
        lda SK_DECK,y
        sta SK_DECK,x
        pla
        sta SK_DECK,y
        dec sk_shuffle_index
        bne .dkr_shuffle
.dkr_done:
        rts

; -----------------------------------------------------------------------------
; Put the card in A on top of the discard pile.
; -----------------------------------------------------------------------------
sk_discard_push:
        ldx SK_DISCARD_COUNT
        cpx #52
        bcs .dku_full
        sta SK_DISCARD,x
        inc SK_DISCARD_COUNT
.dku_full:
        rts

; -----------------------------------------------------------------------------
; A = top of the discard pile. Preserves X and Y.
; -----------------------------------------------------------------------------
sk_discard_top:
        ldy SK_DISCARD_COUNT
        beq .dkt_empty
        dey
        lda SK_DISCARD,y
        rts
.dkt_empty:
        lda #0
        rts

sk_card_temp:       !byte 0
sk_new_players:     !byte 0
sk_shuffle_index:   !byte 0
sk_deal_size:       !byte 0
sk_deal_remaining:  !byte 0
