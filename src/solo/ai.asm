; =============================================================================
; SOLO OPPONENT
; =============================================================================
; Deliberately plain: first legal play, otherwise draw. The mandatory play rule
; means a seat's real choice is usually narrow, and a kernel that has to agree
; with the rules on every turn is worth more than one that plays well. The one
; judgement it makes is which suit to name on an ace, where naming a suit it
; actually holds is the difference between a useful ace and a wasted one.

; -----------------------------------------------------------------------------
; Choose a play for the current seat.
; Out: Y = hand index to play, X = suit to nominate (meaningful only for an
;      ace), C set when there is a play. C clear means draw.
; Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
sk_ai_choose:
        lda SK_CURRENT_PLAYER
        tax
        lda SK_HANDLEN,x
        sta sk_ai_len
        ldy #0
.aic_scan:
        cpy sk_ai_len
        bcs .aic_none
        sty sk_ai_index
        ldx SK_CURRENT_PLAYER
        jsr sk_hand_get
        jsr sk_card_playable
        bcs .aic_found
        ldy sk_ai_index
        iny
        bne .aic_scan
.aic_none:
        clc
        rts

.aic_found:
        jsr sk_ai_pick_suit
        tax
        ldy sk_ai_index
        sec
        rts

; -----------------------------------------------------------------------------
; Which suit should this seat name if it is playing an ace?
; The suit it holds most of, counting the rest of the hand. Ties go to the
; lowest suit index so the choice stays deterministic for a given seed.
; Out: A = suit 0-3. Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
sk_ai_pick_suit:
        lda #0
        sta sk_ai_counts
        sta sk_ai_counts+1
        sta sk_ai_counts+2
        sta sk_ai_counts+3

        ldy #0
.aip_count:
        cpy sk_ai_len
        bcs .aip_best
        cpy sk_ai_index
        beq .aip_next            ; the ace itself does not vote
        sty sk_ai_scan
        ldx SK_CURRENT_PLAYER
        jsr sk_hand_get
        jsr sk_card_suit
        tax
        inc sk_ai_counts,x
        ldy sk_ai_scan
.aip_next:
        iny
        bne .aip_count

.aip_best:
        ldx #0                  ; best suit so far
        ldy #1
.aip_compare:
        lda sk_ai_counts,y
        cmp sk_ai_counts,x
        bcc .aip_keep
        beq .aip_keep            ; ties keep the lower index
        tya
        tax
.aip_keep:
        iny
        cpy #4
        bcc .aip_compare
        txa
        rts

sk_ai_len:    !byte 0
sk_ai_index:  !byte 0
sk_ai_scan:   !byte 0
sk_ai_counts: !byte 0, 0, 0, 0
