; =============================================================================
; ZERO PAGE VARIABLE DEFINITIONS
; =============================================================================
; Zero page ($00-$FF) provides fast 2-byte addressing on 6502.
; $02-$7F is available for user programs.
; We use $02-$3F for our variables.

; -----------------------------------------------------------------------------
; Temporary Registers ($02-$05)
; -----------------------------------------------------------------------------
; Scratch space for calculations and subroutine parameters
zp_temp1        = $02
zp_temp2        = $03
zp_temp3        = $04
zp_temp4        = $05

; -----------------------------------------------------------------------------
; Pointers ($06-$09)
; -----------------------------------------------------------------------------
; 16-bit pointers for indirect addressing
zp_ptr1         = $06           ; $06-$07 - general purpose pointer
zp_ptr2         = $08           ; $08-$09 - general purpose pointer

; -----------------------------------------------------------------------------
; Serial State ($0A-$0D)
; -----------------------------------------------------------------------------
; Ring buffer indices for serial I/O
zp_rx_head      = $0a           ; Receive buffer head index
zp_rx_tail      = $0b           ; Receive buffer tail index
zp_tx_head      = $0c           ; Transmit buffer head index
zp_tx_tail      = $0d           ; Transmit buffer tail index

; -----------------------------------------------------------------------------
; Protocol State ($10-$17)
; -----------------------------------------------------------------------------
; RUBP protocol tracking
zp_player_id    = $10           ; $10-$11 - our assigned player ID (16-bit BE)
zp_game_id      = $12           ; $12-$13 - current game ID (16-bit BE)
zp_sequence     = $14           ; $14-$15 - message sequence number (16-bit BE)
zp_my_index     = $16           ; Our player index in game (0-7)
zp_current_turn = $17           ; Whose turn it is (0-7)

; -----------------------------------------------------------------------------
; Hand State ($18-$1B)
; -----------------------------------------------------------------------------
; Player's card hand management
zp_hand_count   = $18           ; Number of cards in our hand (0-32)
zp_cursor_pos   = $19           ; Cursor position in hand (0-31)
zp_selected_lo  = $1a           ; Selection bitmask low byte (cards 0-7)
zp_selected_hi  = $1b           ; Selection bitmask high byte (cards 8-15)

; -----------------------------------------------------------------------------
; Screen State ($20-$23)
; -----------------------------------------------------------------------------
; Screen rendering helpers
zp_screen_ptr   = $20           ; $20-$21 - screen RAM pointer
zp_color_ptr    = $22           ; $22-$23 - color RAM pointer

; -----------------------------------------------------------------------------
; Connection State ($30)
; -----------------------------------------------------------------------------
; State machine for connection flow
zp_conn_state   = $30
; Connection states:
CONN_DISCONNECTED = 0           ; Not connected
CONN_DIALING      = 1           ; Sent ATDT, waiting CONNECT
CONN_HANDSHAKE    = 2           ; TCP connected, sending HELLO
CONN_WAITING      = 3           ; Got WELCOME, waiting for GAME_START
CONN_PLAYING      = 4           ; Game in progress
