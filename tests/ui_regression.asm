; Real production routines, with only transport output suppressed. The Python
; runner points SYS at test_start; the shipping entry and build are unchanged.
        !source "src/main.asm"
        * = $9000
test_start:
        jsr init_buffers
        lda #0
        sta zp_my_index
        sta zp_current_turn
        jsr screen_init
        jsr draw_game_screen
        lda #$60
        sta transport_send_frame
        lda #$ff
        sta NOMINATED_SUIT
        lda #14
        sta DISCARD_TOP
        lda #32
        sta zp_hand_count
        lda #31
        sta zp_cursor_pos
        ldx #31
        lda #2
.fill:
        sta MY_HAND,x
        dex
        bpl .fill
        ldx #7
        lda #5
.players:
        sta PLAYER_COUNTS,x
        dex
        bpl .players
        lda #32
        sta PLAYER_COUNTS
        lda #10
        sta PLAYER_COUNTS+1
        lda #18
        sta DECK_COUNT
        lda #8
        sta PENDING_DRAWS
        jsr redraw_game
        lda #$40
        jsr capture
        ; Shrinking hand, resolved attack and removed nomination must erase.
        lda #2
        sta zp_hand_count
        lda #0
        sta zp_cursor_pos
        sta PENDING_DRAWS
        jsr redraw_game
        lda #$44
        jsr capture
        ; Real GETIN path must retain the key while checking whose turn it is.
        lda #$1d
        jsr key
        jsr check_input
        lda zp_cursor_pos
        sta $c400
        lda #' '
        jsr key
        jsr check_input
        lda SELECTED_CARDS+1
        sta $c401
        lda #'P'
        jsr key
        jsr check_input
        lda SERIAL_TX_BUF+5
        sta $c402
        lda #'D'
        jsr key
        jsr check_input
        lda SERIAL_TX_BUF+5
        sta $c403
        ; Input during another seat's turn must do nothing.
        lda #1
        sta zp_current_turn
        lda #$1d
        jsr key
        jsr check_input
        lda zp_cursor_pos
        sta $c404
        ; Empty hands cannot move the cursor to 255 or select a phantom card.
        lda #0
        sta zp_current_turn
        sta zp_hand_count
        sta zp_cursor_pos
        lda #$9d
        jsr key
        jsr check_input
        lda zp_cursor_pos
        sta $c405
        ; Both online and solo callers receive the chosen suit.
        lda #'C'
        jsr key
        jsr get_suit_nomination
        sta $c406
        lda zp_temp2
        sta $c407
        ; The survivor must be shown as last, never congratulated.
        lda #0
        sta WINNER_INDEX
        jsr draw_result
        lda #$48
        jsr capture
        lda #1
        sta WINNER_INDEX
        jsr draw_result
        lda #$4c
        jsr capture
        lda #1
        sta transport_link_down
        jsr wait_for_game
        sta $c408
        lda #0
        sta zp_transport
        sta rx_ring_head
        sta rx_ring_tail
        jsr transport_available
        sta $c409
        lda #1
        sta rx_ring_head
        jsr transport_available
        sta $c40a
        ; Receive a complete frame starting at a nonzero ring offset. A ring
        ; reader that overwrites X corrupts the frame assembly index.
        ldx #63
.ring_frame:
        txa
        sta rx_ring+17,x
        dex
        bpl .ring_frame
        ldx #3
.ring_magic:
        lda rubp_magic,x
        sta rx_ring+17,x
        dex
        bpl .ring_magic
        lda #17
        sta rx_ring_tail
        lda #81
        sta rx_ring_head
        jsr transport_receive_frame
        sta $c40b
        lda SERIAL_RX_BUF+63
        sta $c40c
        ; An online replacement can remove the card under the cursor. Exercise
        ; the real parser, then Space/P, rather than repairing the test's state.
        lda #6
        sta zp_hand_count
        lda #5
        sta zp_cursor_pos
        ldx #5
.replacement:
        lda replacement_hand,x
        sta SERIAL_RX_BUF+PAYLOAD_START,x
        dex
        bpl .replacement
        jsr rubp_parse_game_start
        lda zp_hand_count
        sta $c410
        lda zp_cursor_pos
        sta $c411
        lda #' '
        jsr key
        jsr check_input
        lda SELECTED_CARDS
        sta $c412
        lda SELECTED_CARDS+5
        sta $c413
        lda #'P'
        jsr key
        jsr check_input
        lda SERIAL_TX_BUF+5
        sta $c414
        lda SERIAL_TX_BUF+PAYLOAD_START
        sta $c415
        lda SERIAL_TX_BUF+PAYLOAD_START+1
        sta $c416
        ; A replacement must retain a cursor that still points to a card.
        lda #3
        sta zp_cursor_pos
        jsr rubp_parse_game_start
        lda zp_cursor_pos
        sta $c417
        ; Drawing appends a card without moving a valid cursor.
        lda #4
        sta zp_cursor_pos
        lda #1
        sta SERIAL_RX_BUF+PAYLOAD_START
        lda #6
        sta SERIAL_RX_BUF+PAYLOAD_START+1
        jsr rubp_parse_card_drawn
        lda zp_hand_count
        sta $c418
        lda zp_cursor_pos
        sta $c419
        lda MY_HAND+5
        sta $c41a
        ; Going out leaves a safe cursor and no selectable phantom card.
        lda #0
        sta SERIAL_RX_BUF+PAYLOAD_START
        jsr rubp_parse_game_start
        lda zp_hand_count
        sta $c41b
        lda zp_cursor_pos
        sta $c41c
        lda #' '
        jsr key
        jsr check_input
        lda SELECTED_CARDS
        sta $c41d
        lda #$aa
        sta $c40f
.halt:
        jmp .halt
replacement_hand:
        !byte 5,141,201,66,131,9
key:
        sta $0277
        lda #1
        sta $c6
        rts
capture:
        sta zp_ptr2+1
        lda #0
        sta zp_ptr2
        sta zp_ptr1
        lda #4
        sta zp_ptr1+1
        ldx #4
        ldy #0
.copy:
        lda (zp_ptr1),y
        sta (zp_ptr2),y
        iny
        bne .copy
        inc zp_ptr1+1
        inc zp_ptr2+1
        dex
        bne .copy
        rts
