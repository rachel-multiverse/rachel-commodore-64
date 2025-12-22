; =============================================================================
; FIXED MEMORY BUFFERS - DEFINITIONS ONLY
; =============================================================================
; Buffer locations in low RAM ($0200-$03FF)
; This area is safe to use on C64 (not used by BASIC/KERNAL)
;
; NOTE: This file contains only symbol definitions (no code).
; The init_buffers routine is in main.asm after the program counter is set.

; -----------------------------------------------------------------------------
; Serial Buffers ($0200-$02FF)
; -----------------------------------------------------------------------------
; 64-byte buffers for RUBP messages (matches protocol message size)

SERIAL_RX_BUF   = $0200         ; 64 bytes - receive buffer for incoming msg
SERIAL_TX_BUF   = $0240         ; 64 bytes - transmit buffer for outgoing msg
AT_CMD_BUF      = $0280         ; 64 bytes - AT command assembly
AT_RESP_BUF     = $02c0         ; 64 bytes - AT response parsing

; -----------------------------------------------------------------------------
; Game State Buffers ($0300-$03FF)
; -----------------------------------------------------------------------------

PLAYER_NAMES    = $0300         ; 8 players x 16 chars = 128 bytes ($0300-$037F)
PLAYER_COUNTS   = $0380         ; 8 bytes - card count per player
MY_HAND         = $0388         ; 32 bytes - our hand (max 32 cards)
DISCARD_TOP     = $03a8         ; 1 byte - top card of discard pile
NOMINATED_SUIT  = $03a9         ; 1 byte - nominated suit (0-3 or $FF=none)
PENDING_DRAWS   = $03aa         ; 1 byte - cards we must draw (attack)
PENDING_SKIPS   = $03ab         ; 1 byte - skips pending
DECK_COUNT      = $03ac         ; 1 byte - cards remaining in deck
DIRECTION       = $03ad         ; 1 byte - 0=clockwise, 1=counter-clockwise
GAME_OVER       = $03ae         ; 1 byte - 0=playing, 1=game over
WINNER_INDEX    = $03af         ; 1 byte - winner player index

; -----------------------------------------------------------------------------
; Buffer Size Constants
; -----------------------------------------------------------------------------

RUBP_MSG_SIZE   = 64            ; RUBP protocol message size
MAX_HAND_SIZE   = 32            ; Maximum cards in hand
MAX_PLAYERS     = 8             ; Maximum players per game
NAME_LENGTH     = 16            ; Player name length
