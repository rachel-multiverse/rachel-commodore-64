; =============================================================================
; SOLO HAND STORAGE
; =============================================================================
; One card per byte, SK_SEAT_STRIDE bytes per seat, with the count kept
; separately in SK_HANDLEN. Removal closes the gap so a hand is always a dense
; run from index zero, which is what the renderer and the action scan both
; assume.

; -----------------------------------------------------------------------------
; Add a card to a seat's hand.
; In: A = card, X = seat. Clobbers: A, Y.
; -----------------------------------------------------------------------------
sk_hand_add:
        sta sk_hand_card
        txa
        jsr sk_hand_base
        ldy SK_HANDLEN,x
        cpy #SK_SEAT_STRIDE
        bcs .hna_full            ; a seat cannot hold more than the deck
        lda sk_hand_card
        sta (zp_ptr1),y
        inc SK_HANDLEN,x
.hna_full:
        rts

; -----------------------------------------------------------------------------
; Remove the card at index Y from a seat's hand, closing the gap.
; In: X = seat, Y = index. Clobbers: A, Y.
; -----------------------------------------------------------------------------
sk_hand_remove:
        lda SK_HANDLEN,x
        sta sk_hand_len         ; CPY cannot index, so the length is parked here
        txa
        jsr sk_hand_base
        cpy sk_hand_len
        bcs .hnr_done            ; index past the end: nothing to remove
.hnr_shift:
        iny
        cpy sk_hand_len
        bcs .hnr_shrink
        lda (zp_ptr1),y
        dey
        sta (zp_ptr1),y
        iny
        bne .hnr_shift
.hnr_shrink:
        dec SK_HANDLEN,x
.hnr_done:
        rts

; -----------------------------------------------------------------------------
; Read the card at index Y of a seat's hand.
; In: X = seat, Y = index. Out: A = card. Clobbers: A.
; -----------------------------------------------------------------------------
sk_hand_get:
        txa
        jsr sk_hand_base
        lda (zp_ptr1),y
        rts

sk_hand_card: !byte 0
sk_hand_len:  !byte 0
