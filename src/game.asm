; =============================================================================
; GAME MODULE
; =============================================================================
; Card display and game state rendering

; -----------------------------------------------------------------------------
; Card Encoding (from RUBP spec)
; -----------------------------------------------------------------------------
; Bits 7-6: Suit (00=Hearts, 01=Diamonds, 10=Clubs, 11=Spades)
; Bits 5-0: Rank (2-14, where 11=J, 12=Q, 13=K, 14=A)

; Suit characters (PETSCII has card suits!)
SUIT_HEART      = $53           ; S for now (PETSCII heart = $53 in graphics mode)
SUIT_DIAMOND    = $5a           ; Z for now
SUIT_CLUB       = $58           ; X for now
SUIT_SPADE      = $41           ; A for now

; Actually let's use letters for clarity on text screen
; H=Hearts, D=Diamonds, C=Clubs, S=Spades

; =============================================================================
; CARD DISPLAY
; =============================================================================

; -----------------------------------------------------------------------------
; Decode card byte
; Input: A = encoded card
; Output: X = suit (0-3), Y = rank (2-14)
; -----------------------------------------------------------------------------
decode_card:
        sta zp_temp1
        and #$3f                ; Mask lower 6 bits = rank
        tay                     ; Y = rank (2-14)

        lda zp_temp1
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr                     ; Shift suit to bits 0-1
        tax                     ; X = suit (0-3)
        rts

; -----------------------------------------------------------------------------
; Print card at current cursor position (3 chars: rank + suit + space)
; Input: A = encoded card
; Clobbers: A, X, Y, zp_temp1
; -----------------------------------------------------------------------------
print_card:
        jsr decode_card         ; X=suit, Y=rank

        ; Set color based on suit (red for hearts/diamonds)
        cpx #2                  ; Clubs(2) or Spades(3)?
        bcs .black_suit
        lda #COL_LIGHT_RED      ; readable against the blue table
        bne .set_color
.black_suit:
        lda #COL_WHITE          ; Clubs/Spades = white
.set_color:
        sta $0286

        ; Print rank character
        lda rank_chars,y
        jsr CHROUT

        ; Print suit character
        lda suit_chars,x
        jsr CHROUT

        ; Reset color to white
        lda #COL_WHITE
        sta $0286

        ; Space after card
        lda #' '
        jsr CHROUT
        rts

; Rank characters (index 0-14, 0-1 unused)
rank_chars:
        !text "??23456789TJQKA"

; Suit characters
suit_chars:
        !text "HDCS"            ; Hearts, Diamonds, Clubs, Spades

; -----------------------------------------------------------------------------
; Draw player's hand (row 14-17)
; Shows cards with selection brackets
; -----------------------------------------------------------------------------
draw_hand:
        ; Four rows of eight five-character slots cover every supported hand.
        ; Erase old cards as well as redrawing current ones after a hand shrinks.
        ldy #14
.dh_clear:
        tya
        pha
        jsr screen_clear_row
        pla
        tay
        iny
        cpy #18
        bne .dh_clear
        ldx #0
.dh_card:
        cpx zp_hand_count
        bcs .dh_done
        stx zp_temp4
        txa
        and #7
        sta zp_temp3
        asl
        asl
        clc
        adc zp_temp3            ; column = (index % 8) * 5
        pha
        txa
        lsr
        lsr
        lsr
        clc
        adc #14
        tay
        pla
        tax
        jsr screen_goto
        ldx zp_temp4
        cpx zp_cursor_pos
        bne .dh_plain
        lda #$12                ; reverse video marks the entire current card
        jsr CHROUT
.dh_plain:
        lda #' '
        ldx zp_temp4
        cpx zp_cursor_pos
        bne .dh_marker
        lda #'>'
.dh_marker:
        ldy SELECTED_CARDS,x
        beq .dh_unselected
        lda #'*'
.dh_unselected:
        jsr CHROUT
        ldx zp_temp4
        lda MY_HAND,x
        jsr print_card
        lda #$92
        jsr CHROUT
        ldx zp_temp4
        inx
        jmp .dh_card
.dh_done:
        rts

; -----------------------------------------------------------------------------
; Draw discard pile (centered, rows 6-9)
; -----------------------------------------------------------------------------
draw_discard:
        ldy #7
        jsr screen_clear_row
        ; Draw card box
        ldx #17
        ldy #6
        clc
        jsr screen_goto

        ; Top of box
        lda #'+'                ; simple, legible card outline
        jsr CHROUT
        lda #$60                ; Horizontal line
        jsr CHROUT
        jsr CHROUT
        jsr CHROUT
        jsr CHROUT
        lda #'+'                ; Top-right corner
        jsr CHROUT

        ; Middle row with card
        ldx #17
        ldy #7
        clc
        jsr screen_goto
        lda #$5d                ; Vertical bar
        jsr CHROUT
        lda #' '
        jsr CHROUT

        ; Print the top card
        lda DISCARD_TOP
        jsr print_card

        lda #$5d                ; Vertical bar
        jsr CHROUT

        ; Bottom of box
        ldx #17
        ldy #8
        clc
        jsr screen_goto
        lda #'+'                ; Bottom-left
        jsr CHROUT
        lda #$60
        jsr CHROUT
        jsr CHROUT
        jsr CHROUT
        jsr CHROUT
        lda #'+'                ; Bottom-right
        jsr CHROUT

        ; Show nominated suit if active
        lda NOMINATED_SUIT
        cmp #$ff
        beq .no_nomination

        ldx #25
        ldy #7
        clc
        jsr screen_goto

        ldx NOMINATED_SUIT
        lda suit_names,x
        sta zp_ptr1
        lda suit_names+1,x
        sta zp_ptr1+1
        ; Print suit name... actually just print the letter for now
        lda suit_chars,x
        jsr CHROUT

.no_nomination:
        rts

; Suit names (for display)
suit_names:
        !word txt_hearts, txt_diamonds, txt_clubs, txt_spades

txt_hearts:   !text "HEARTS"
              !byte 0
txt_diamonds: !text "DIAMONDS"
              !byte 0
txt_clubs:    !text "CLUBS"
              !byte 0
txt_spades:   !text "SPADES"
              !byte 0

; -----------------------------------------------------------------------------
; Draw player list (rows 2-3)
; -----------------------------------------------------------------------------
draw_players:
        ldy #2
        jsr screen_clear_row
        ldy #3
        jsr screen_clear_row
        ldx #0                  ; Player index

.player_loop:
        cpx #MAX_PLAYERS
        beq .players_done

        stx zp_temp4            ; Save player index

        ; Check if player exists (has cards or is us)
        lda PLAYER_COUNTS,x
        bne .has_player
        cpx zp_my_index
        bne .next_player

.has_player:
        ; Calculate screen position
        ; Row 2 for players 0-3, row 3 for 4-7
        ; Column = (index mod 4) * 10
        txa
        and #$03                ; mod 4
        asl
        asl
        asl                     ; * 8
        clc
        adc #1                  ; +1 margin
        sta zp_temp1            ; Column

        txa
        lsr
        lsr                     ; / 4
        clc
        adc #2                  ; Base row 2
        tay                     ; Row

        ldx zp_temp1
        clc
        jsr screen_goto

        ; Check if current turn - show marker
        ldx zp_temp4
        cpx zp_current_turn
        bne .not_current_turn
        lda #'>'
        jsr CHROUT
        bne .print_player_info
.not_current_turn:
        lda #' '
        jsr CHROUT

.print_player_info:
        ; Print "Pn:" where n is player number
        lda #'P'
        jsr CHROUT
        ldx zp_temp4
        txa
        clc
        adc #'1'                ; Player 1-8
        jsr CHROUT
        lda #':'
        jsr CHROUT

        ; Print card count
        lda PLAYER_COUNTS,x
        jsr print_digit

        ; Closing marker if current turn
        ldx zp_temp4
        cpx zp_current_turn
        bne .no_close_marker
        lda #'<'
        jsr CHROUT
.no_close_marker:

.next_player:
        ldx zp_temp4
        inx
        jmp .player_loop

.players_done:
        rts

; -----------------------------------------------------------------------------
; Print single digit (0-9)
; Input: A = number (0-99, only prints ones digit if >9)
; -----------------------------------------------------------------------------
print_digit:
        cmp #10
        bcc .single
        ; Two digits - print tens
        ldx #0
.tens:
        cmp #10
        bcc .print_tens
        sbc #10
        inx
        bne .tens
.print_tens:
        pha
        txa
        clc
        adc #'0'
        jsr CHROUT
        pla
.single:
        clc
        adc #'0'
        jsr CHROUT
        rts

; -----------------------------------------------------------------------------
; Draw game info line (row 10)
; -----------------------------------------------------------------------------
draw_game_info:
        ldy #10
        jsr screen_clear_row
        ldx #5
        ldy #10
        clc
        jsr screen_goto

        ; Deck count
        lda #<txt_deck
        sta zp_ptr1
        lda #>txt_deck
        sta zp_ptr1+1
        jsr screen_print

        lda DECK_COUNT
        jsr print_digit

        ; Pending draws
        lda PENDING_DRAWS
        beq .no_pending

        lda #' '
        jsr CHROUT
        jsr CHROUT

        lda #<txt_pending
        sta zp_ptr1
        lda #>txt_pending
        sta zp_ptr1+1
        jsr screen_print

        lda #'+'
        jsr CHROUT
        lda PENDING_DRAWS
        jsr print_digit

.no_pending:
        rts

txt_deck:
        !text "DECK:"
        !byte 0

txt_pending:
        !text "DRAW "
        !byte 0

; -----------------------------------------------------------------------------
; Draw status line (row 24)
; -----------------------------------------------------------------------------
draw_status:
        ldx #1
        ldy #24
        clc
        jsr screen_goto

        ; Clear line first
        lda #' '
        ldx #38
.clear_status:
        jsr CHROUT
        dex
        bne .clear_status

        ; Reposition
        ldx #1
        ldy #24
        clc
        jsr screen_goto

        ; Check whose turn
        lda zp_current_turn
        cmp zp_my_index
        bne .not_my_turn

        lda #<txt_your_turn
        sta zp_ptr1
        lda #>txt_your_turn
        sta zp_ptr1+1
        jmp screen_print

.not_my_turn:
        lda #<txt_waiting_turn
        sta zp_ptr1
        lda #>txt_waiting_turn
        sta zp_ptr1+1
        jmp screen_print

txt_your_turn:
        !text "YOUR TURN - SELECT AND PRESS P"
        !byte 0

txt_waiting_turn:
        !text "WAITING FOR OTHER PLAYERS..."
        !byte 0

; -----------------------------------------------------------------------------
; Redraw entire game state
; -----------------------------------------------------------------------------
redraw_game:
        jsr draw_players
        jsr draw_discard
        jsr draw_game_info
        jsr draw_hand
        jsr draw_status
        rts
