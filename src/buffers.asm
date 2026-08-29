; =============================================================================
; FIXED MEMORY BUFFERS - DEFINITIONS ONLY
; =============================================================================
; Buffer locations in free RAM ($C100-$C2FF). Page $03 is not application
; scratch space on a C64: it contains KERNAL vectors and the cassette buffer.
;
; NOTE: This file contains only symbol definitions (no code).
; The init_buffers routine is in main.asm after the program counter is set.

; -----------------------------------------------------------------------------
; Serial Buffers ($C100-$C1FF)
; -----------------------------------------------------------------------------
; 64-byte buffers for RUBP messages (matches protocol message size)

SERIAL_RX_BUF   = $c100
SERIAL_TX_BUF   = $c140
AT_CMD_BUF      = $c180
AT_RESP_BUF     = $c1c0

; -----------------------------------------------------------------------------
; Game State Buffers ($C200-$C2FF)
; -----------------------------------------------------------------------------

PLAYER_NAMES    = $c200
PLAYER_COUNTS   = $c280
MY_HAND         = $c288
DISCARD_TOP     = $c2a8
NOMINATED_SUIT  = $c2a9
PENDING_DRAWS   = $c2aa
PENDING_SKIPS   = $c2ab
DECK_COUNT      = $c2ac
DIRECTION       = $c2ad
GAME_OVER       = $c2ae
WINNER_INDEX    = $c2af
IP_INPUT_BUF    = $c2b0

; Last authoritative state hash seen in a GAME_STATE, echoed back as the
; ObservedStateHash in PLAY_CARD / DRAW_CARD so the host can reject stale plays.
OBSERVED_HASH   = $c2d0
HASH_VALID      = $c2d8
SELECTED_CARDS  = $c2d9         ; 32 one-byte booleans, cards 0-31

; -----------------------------------------------------------------------------
; Buffer Size Constants
; -----------------------------------------------------------------------------

RUBP_MSG_SIZE   = 64            ; RUBP protocol message size
MAX_HAND_SIZE   = 32            ; Maximum cards in hand
MAX_PLAYERS     = 8             ; Maximum players per game
NAME_LENGTH     = 16            ; Player name length
