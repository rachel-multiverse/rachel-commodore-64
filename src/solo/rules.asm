; =============================================================================
; SOLO RULES
; =============================================================================
; docs/GAME_RULES.md is the single source of truth; this file implements it and
; nothing else. Where a rule reads oddly, the rule wins.

; -----------------------------------------------------------------------------
; Can the card in A be played right now?
; Out: C set when playable, clear when not. Clobbers: A, Y.
;
; The three cases are exclusive and checked in the rules' own order: a live
; skip, then a live draw attack, then ordinary matching.
; -----------------------------------------------------------------------------
sk_card_playable:
        sta sk_test_card

        lda SK_PENDING_SKIPS
        beq .rcp_check_draws
        ; Facing 7s, only a 7 answers.
        lda sk_test_card
        jsr sk_card_rank
        cmp #RANK_SEVEN
        beq .rcp_yes
        clc
        rts

.rcp_check_draws:
        lda SK_PENDING_DRAWS
        beq .rcp_normal
        ; Facing an attack, only the rank that made it answers: a 2 for 2s, a
        ; jack for jacks. A red jack is still a jack, which is how it gets to
        ; blunt a black one.
        jsr sk_discard_top
        jsr sk_card_rank
        sta sk_test_rank
        lda sk_test_card
        jsr sk_card_rank
        cmp sk_test_rank
        beq .rcp_yes
        clc
        rts

.rcp_normal:
        ; A live nomination replaces the top card's suit: follow the named suit
        ; or play another ace.
        lda SK_NOMINATED_SUIT
        cmp #SK_NO_SUIT
        beq .rcp_match_top

        sta sk_test_rank        ; the nominated suit
        lda sk_test_card
        jsr sk_card_suit
        cmp sk_test_rank
        beq .rcp_yes
        lda sk_test_card
        jsr sk_card_rank
        cmp #RANK_ACE
        beq .rcp_yes
        clc
        rts

.rcp_match_top:
        ; Same suit or same rank as the card showing.
        jsr sk_discard_top
        sta sk_test_top
        jsr sk_card_rank
        sta sk_test_rank
        lda sk_test_card
        jsr sk_card_rank
        cmp sk_test_rank
        beq .rcp_yes

        lda sk_test_top
        jsr sk_card_suit
        sta sk_test_rank
        lda sk_test_card
        jsr sk_card_suit
        cmp sk_test_rank
        beq .rcp_yes
        clc
        rts

.rcp_yes:
        sec
        rts

; -----------------------------------------------------------------------------
; Does the seat in A hold any legal play?
; Out: C set when it does. Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
sk_seat_has_play:
        tax
        lda SK_HANDLEN,x
        sta sk_scan_len
        txa
        jsr sk_hand_base
        ldy #0
.rhp_loop:
        cpy sk_scan_len
        bcs .rhp_none
        lda (zp_ptr1),y
        sty sk_scan_index
        jsr sk_card_playable
        ldy sk_scan_index
        bcs .rhp_yes
        iny
        bne .rhp_loop
.rhp_none:
        clc
        rts
.rhp_yes:
        sec
        rts

; -----------------------------------------------------------------------------
; Apply the effect of playing the card in A for the current seat.
; In:  A = card, X = nominated suit when the card is an ace (else ignored).
; Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
sk_apply_card:
        sta sk_played_card
        stx sk_played_suit
        jsr sk_discard_push

        lda sk_played_card
        jsr sk_card_rank
        cmp #RANK_TWO
        beq .rac_two
        cmp #RANK_SEVEN
        beq .rac_seven
        cmp #RANK_JACK
        beq .rac_jack
        cmp #RANK_QUEEN
        beq .rac_queen
        cmp #RANK_ACE
        beq .rac_ace

.rac_plain:
        ; Any card that is not an ace ends the nomination it was following.
        lda #SK_NO_SUIT
        sta SK_NOMINATED_SUIT
        rts

.rac_two:
        lda SK_PENDING_DRAWS
        clc
        adc #2
        sta SK_PENDING_DRAWS
        jmp .rac_plain

.rac_seven:
        inc SK_PENDING_SKIPS
        jmp .rac_plain

.rac_jack:
        lda sk_played_card
        jsr sk_card_suit
        cmp #SUIT_CLUBS
        bcs .rac_black_jack
        ; Red jack: blunts a live black-jack attack by five, and is an ordinary
        ; card when there is no attack to blunt.
        lda SK_PENDING_DRAWS
        cmp #5
        bcc .rac_plain
        sec
        sbc #5
        sta SK_PENDING_DRAWS
        jmp .rac_plain
.rac_black_jack:
        lda SK_PENDING_DRAWS
        clc
        adc #5
        sta SK_PENDING_DRAWS
        jmp .rac_plain

.rac_queen:
        lda SK_DIRECTION
        eor #1
        sta SK_DIRECTION
        jmp .rac_plain

.rac_ace:
        lda sk_played_suit
        sta SK_NOMINATED_SUIT
        rts

; -----------------------------------------------------------------------------
; Move to the next seat that is still in, in the current direction.
; Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
sk_step_seat:
        ldx #0                  ; guard against a table with nobody left
.rss_step:
        lda SK_DIRECTION
        bne .rss_back
        inc SK_CURRENT_PLAYER
        lda SK_CURRENT_PLAYER
        cmp SK_PLAYER_COUNT
        bcc .rss_check
        lda #0
        sta SK_CURRENT_PLAYER
        beq .rss_check
.rss_back:
        dec SK_CURRENT_PLAYER
        bpl .rss_check
        lda SK_PLAYER_COUNT
        sec
        sbc #1
        sta SK_CURRENT_PLAYER
.rss_check:
        lda SK_CURRENT_PLAYER
        jsr sk_seat_is_out
        beq .rss_done            ; not out, so this seat plays
        inx
        cpx #SK_MAX_PLAYERS
        bcc .rss_step
.rss_done:
        rts

; -----------------------------------------------------------------------------
; Record that the current seat has emptied its hand.
; Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
sk_seat_finished:
        ldy SK_CURRENT_PLAYER
        lda sk_seat_bit,y
        ora SK_OUT_MASK
        sta SK_OUT_MASK
        ldx SK_FINISH_COUNT
        tya
        sta SK_FINISH_ORDER,x
        inc SK_FINISH_COUNT
        rts

; -----------------------------------------------------------------------------
; How many seats are still holding cards?
; Out: A = count. Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
sk_seats_remaining:
        lda SK_PLAYER_COUNT
        sec
        sbc SK_FINISH_COUNT
        rts

; -----------------------------------------------------------------------------
; Is the game over? The last seat holding cards finishes last.
; Out: C set when the game is over. Clobbers: A.
;
; Spelled out rather than left as the carry from `cmp #2`, which is set when
; two or more seats remain — the opposite of the question being asked.
; -----------------------------------------------------------------------------
sk_game_over:
        jsr sk_seats_remaining
        cmp #2
        bcs .rgo_playing
        sec
        rts
.rgo_playing:
        clc
        rts

sk_test_card:    !byte 0
sk_test_rank:    !byte 0
sk_test_top:     !byte 0
sk_played_card:  !byte 0
sk_played_suit:  !byte 0
sk_scan_seat:    !byte 0
sk_scan_index:   !byte 0
sk_scan_len:     !byte 0
