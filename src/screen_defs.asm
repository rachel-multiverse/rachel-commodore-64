; =============================================================================
; SCREEN MODULE - DEFINITIONS ONLY
; =============================================================================
; Constants for screen rendering. No executable code.
; Include BEFORE the program counter is set.

; -----------------------------------------------------------------------------
; Screen Constants
; -----------------------------------------------------------------------------

SCREEN_RAM      = $0400         ; Default screen memory
COLOR_RAM       = $d800         ; Color RAM
SCREEN_WIDTH    = 40
SCREEN_HEIGHT   = 25

; -----------------------------------------------------------------------------
; C64 Color Codes
; -----------------------------------------------------------------------------

COL_BLACK       = 0
COL_WHITE       = 1
COL_RED         = 2
COL_CYAN        = 3
COL_PURPLE      = 4
COL_GREEN       = 5
COL_BLUE        = 6
COL_YELLOW      = 7
COL_ORANGE      = 8
COL_BROWN       = 9
COL_LIGHT_RED   = 10
COL_DARK_GREY   = 11
COL_GREY        = 12
COL_LIGHT_GREEN = 13
COL_LIGHT_BLUE  = 14
COL_LIGHT_GREY  = 15

; -----------------------------------------------------------------------------
; KERNAL Routines
; -----------------------------------------------------------------------------

CHROUT          = $ffd2         ; Output character to screen
PLOT            = $fff0         ; Set/get cursor position
GETIN           = $ffe4         ; Get character from keyboard buffer
