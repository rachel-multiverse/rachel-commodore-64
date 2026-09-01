; =============================================================================
; SOLO KERNEL STATE
; =============================================================================
; Local rules state for standalone play. Permitted by decision 0006: a client
; may ship a local kernel for solo play, and where it does, the AI seats are
; that platform's own. This kernel never touches the network, and the networked
; path never consults it for legality — that line is decision 0003's and 0006
; does not move it.
;
; The VIC-20 packs its deck into 6-bit ordinals and its hands into 52-bit masks
; because it has 11.5KB for everything. The C64 has the whole $C000 block free,
; so cards are stored one per byte. That costs 400-odd bytes and buys code that
; reads like the rules it implements. It also matches the portable RachelKernel
; state image, which is one encoded card byte per card throughout.
;
; Cards use the same encoding as the network client: suit in the top two bits,
; rank 2-14 in the low six.

SK_STATE          = $c400
SK_DECK           = $c420       ; 52 bytes, index 0 is the next card drawn
SK_DISCARD        = $c460       ; 52 bytes, index 0 is the bottom of the pile
SK_HANDLEN        = $c4a0       ; 8 bytes, cards held per seat
SK_SCRATCH        = $c4b0       ; 8 bytes, PRNG working copy
SK_HANDS          = $c500       ; 8 seats, 64 bytes each

SK_PLAYER_COUNT   = SK_STATE+0
SK_CURRENT_PLAYER = SK_STATE+1
SK_DIRECTION      = SK_STATE+2  ; 0 = clockwise, 1 = counter-clockwise
SK_NOMINATED_SUIT = SK_STATE+3  ; $FF = none
SK_PENDING_DRAWS  = SK_STATE+4
SK_PENDING_SKIPS  = SK_STATE+5
SK_TURN_NUMBER    = SK_STATE+6  ; 4 bytes, big-endian
SK_RANDOM_SEED    = SK_STATE+10 ; 8 bytes, little-endian xorshift64 state
SK_FINISH_COUNT   = SK_STATE+18
SK_FINISH_ORDER   = SK_STATE+19 ; 8 seats, in the order they went out
SK_DECK_COUNT     = SK_STATE+27
SK_DISCARD_COUNT  = SK_STATE+28
SK_OUT_MASK       = SK_STATE+29 ; bit per seat, set once a seat is out
SK_STATE_SIZE     = 30

SK_SEAT_STRIDE    = 64          ; a power of two so a seat base is a shift
SK_MAX_PLAYERS    = 8
SK_NO_SUIT        = $ff

RANK_TWO          = 2
RANK_SEVEN        = 7
RANK_JACK         = 11
RANK_QUEEN        = 12
RANK_ACE          = 14

SUIT_HEARTS       = 0
SUIT_DIAMONDS     = 1
SUIT_CLUBS        = 2
SUIT_SPADES       = 3

; -----------------------------------------------------------------------------
; A = card -> A = suit 0-3. Preserves X and Y.
; -----------------------------------------------------------------------------
sk_card_suit:
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        rts

; -----------------------------------------------------------------------------
; A = card -> A = rank 2-14. Preserves X and Y.
; -----------------------------------------------------------------------------
sk_card_rank:
        and #$3f
        rts

; -----------------------------------------------------------------------------
; A = seat -> zp_ptr1 = that seat's hand. Preserves X and Y.
;
; Seats are 64 bytes apart so the base is a shift rather than a multiply: the
; low two bits of the seat pick the offset within a page pair, the high bit
; picks the page.
; -----------------------------------------------------------------------------
sk_hand_base:
        pha
        and #3
        asl
        asl
        asl
        asl
        asl
        asl                     ; (seat & 3) * 64, at most 192
        sta zp_ptr1
        pla
        lsr
        lsr                     ; seat / 4
        clc
        adc #>SK_HANDS
        sta zp_ptr1+1
        rts

; -----------------------------------------------------------------------------
; A = seat -> Z set when that seat has already gone out. Preserves X, clobbers Y.
; -----------------------------------------------------------------------------
sk_seat_is_out:
        tay
        lda sk_seat_bit,y
        and SK_OUT_MASK
        rts

sk_seat_bit:
        !byte $01, $02, $04, $08, $10, $20, $40, $80
