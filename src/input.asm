; =============================================================================
; INPUT MODULE
; =============================================================================
; Keyboard input handling using KERNAL routines

; -----------------------------------------------------------------------------
; Key Constants (PETSCII codes)
; -----------------------------------------------------------------------------

KEY_RETURN      = $0d           ; Return/Enter
KEY_SPACE       = $20           ; Space bar
KEY_LEFT        = $9d           ; Cursor left
KEY_RIGHT       = $1d           ; Cursor right
KEY_UP          = $91           ; Cursor up
KEY_DOWN        = $11           ; Cursor down

; Letter keys (uppercase PETSCII)
KEY_D           = $44           ; D - Draw
KEY_P           = $50           ; P - Play
KEY_Q           = $51           ; Q - Quit
KEY_Y           = $59           ; Y - Yes
KEY_N           = $4e           ; N - No

; =============================================================================
; INPUT SUBROUTINES
; =============================================================================

; -----------------------------------------------------------------------------
; Scan keyboard (non-blocking)
; Returns: A = key code, or 0 if no key pressed
;          Z flag set if no key
; Clobbers: A
; -----------------------------------------------------------------------------
input_scan:
        jsr GETIN               ; KERNAL get character
        rts

; -----------------------------------------------------------------------------
; Wait for any keypress (blocking)
; Returns: A = key code
; Clobbers: A
; -----------------------------------------------------------------------------
input_wait_key:
-
        jsr GETIN
        beq -                   ; Loop until key pressed
        rts

; -----------------------------------------------------------------------------
; Wait for Return key (blocking)
; Ignores all other keys
; Clobbers: A
; -----------------------------------------------------------------------------
input_wait_return:
-
        jsr GETIN
        beq -                   ; Wait for any key
        cmp #KEY_RETURN
        bne -                   ; Keep waiting if not Return
        rts

; -----------------------------------------------------------------------------
; Wait for Y or N key (blocking)
; Returns: A = KEY_Y or KEY_N
; Clobbers: A
; -----------------------------------------------------------------------------
input_wait_yn:
-
        jsr GETIN
        beq -
        cmp #KEY_Y
        beq +
        cmp #KEY_N
        bne -                   ; Keep waiting
+
        rts

; -----------------------------------------------------------------------------
; Check if specific key was pressed
; Input: A = key to check for
; Returns: Z=1 if that key was pressed, Z=0 otherwise
; Clobbers: A, zp_temp1
; -----------------------------------------------------------------------------
input_check_key:
        sta zp_temp1            ; Save key to check
        jsr GETIN
        cmp zp_temp1
        rts
