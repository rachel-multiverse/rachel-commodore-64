; =============================================================================
; SCREEN MODULE - CODE
; =============================================================================
; PETSCII screen rendering utilities for 40x25 text mode
;
; NOTE: This file contains executable code.
; Include AFTER the program counter is set (after * = $0810)
; Screen constants are in screen_defs.asm

; =============================================================================
; SCREEN SUBROUTINES
; =============================================================================

; Initialize screen with blue background
; Sets border, background, and clears screen
screen_init:
        ; Set border and background to blue
        lda #COL_BLUE
        sta $d020               ; Border
        sta $d021               ; Background

        ; Clear screen (PETSCII $93)
        lda #$93
        jsr CHROUT

        ; Set text color to white
        lda #COL_WHITE
        sta $0286               ; Current text color

        rts

; -----------------------------------------------------------------------------
; Print null-terminated string
; Input: zp_ptr1 = pointer to string
; Clobbers: A, Y
; -----------------------------------------------------------------------------
screen_print:
        ldy #0
-
        lda (zp_ptr1),y
        beq +
        jsr CHROUT
        iny
        bne -
+
        rts

; -----------------------------------------------------------------------------
; Print string at X,Y position
; Input: X = column (0-39), Y = row (0-24), zp_ptr1 = string pointer
; Clobbers: A, X, Y
; -----------------------------------------------------------------------------
screen_print_at:
        clc
        jsr PLOT                ; Set cursor position
        jsr screen_print
        rts

; -----------------------------------------------------------------------------
; Set cursor position
; Input: X = column (0-39), Y = row (0-24)
; Clobbers: A
; -----------------------------------------------------------------------------
screen_goto:
        clc
        jsr PLOT
        rts

; -----------------------------------------------------------------------------
; Draw horizontal line
; Input: X = start column, Y = row, A = length
; Clobbers: A, X, Y, zp_temp1, zp_temp2
; -----------------------------------------------------------------------------
screen_hline:
        stx zp_temp1            ; Save start X
        sta zp_temp2            ; Save length

        clc
        jsr PLOT                ; Position cursor

        ldx zp_temp2            ; Get length
        lda #$40                ; PETSCII horizontal line character
-
        jsr CHROUT
        dex
        bne -
        rts

; -----------------------------------------------------------------------------
; Set text color
; Input: A = color (0-15)
; Clobbers: nothing
; -----------------------------------------------------------------------------
screen_set_color:
        sta $0286
        rts

; -----------------------------------------------------------------------------
; Print a single character multiple times
; Input: A = character, X = count
; Clobbers: A, X
; -----------------------------------------------------------------------------
screen_repeat_char:
        stx zp_temp1
-
        jsr CHROUT
        dec zp_temp1
        bne -
        rts
