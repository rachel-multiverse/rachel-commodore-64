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
        jsr screen_goto                ; Set cursor position
        jsr screen_print
        rts

; -----------------------------------------------------------------------------
; Set cursor position
; Input: X = column (0-39), Y = row (0-24)
; Clobbers: flags
; -----------------------------------------------------------------------------
screen_goto:
        ; Our callers use X=column, Y=row. KERNAL PLOT expects the reverse.
        ; Preserve the caller's registers, including the line character in A.
        pha
        txa
        pha
        tya
        tax
        pla
        tay
        clc
        jsr PLOT
        tya
        pha
        txa
        tay
        pla
        tax
        pla
        rts

; Leave column 39 unused: CHROUT there links two physical rows into one
; logical line (and scrolls on row 24). All table writers use columns 0-38.
; Input Y=row. Clobbers A,X,Y.
screen_clear_row:
        ldx #0
        jsr screen_goto
        lda #' '
        ldx #39
        jsr screen_repeat_char
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
        jsr screen_goto                ; Position cursor

        ldx zp_temp2            ; Get length
        lda #$60                ; PETSCII horizontal line character
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

; =============================================================================
; GAME SCREEN LAYOUT
; =============================================================================

; -----------------------------------------------------------------------------
; Draw the game title bar (centered at row 0)
; -----------------------------------------------------------------------------
draw_title:
        ldx #12                 ; Column (center "RACHEL V1.0")
        ldy #0                  ; Row 0
        clc
        jsr screen_goto

        ldx #0
-
        lda txt_title,x
        beq +
        jsr CHROUT
        inx
        bne -
+
        rts

txt_title:
        !text "RACHEL V1.0"
        !byte 0

; -----------------------------------------------------------------------------
; Draw the main game frame
; Uses PETSCII box drawing characters
; -----------------------------------------------------------------------------
draw_frame:
        ; Row 1: Top border (below title)
        ldx #0
        ldy #1
        lda #39
        jsr screen_hline

        ; Row 4: Below player list
        ldx #0
        ldy #4
        lda #39
        jsr screen_hline

        ; Row 11: Below discard area
        ldx #0
        ldy #11
        lda #39
        jsr screen_hline

        ; Row 19: Below hand area
        ldx #0
        ldy #19
        lda #39
        jsr screen_hline

        ; Row 22: Above status line
        ldx #0
        ldy #22
        lda #39
        jsr screen_hline

        rts

; -----------------------------------------------------------------------------
; Draw the complete game screen (title + frame + labels)
; -----------------------------------------------------------------------------
draw_game_screen:
        jsr draw_title
        jsr draw_frame

        ; "Your hand:" label at row 12
        ldx #1
        ldy #12
        clc
        jsr screen_goto
        ldx #0
-
        lda txt_your_hand,x
        beq +
        jsr CHROUT
        inx
        bne -
+

        ; Controls hint at row 20
        ldx #1
        ldy #20
        clc
        jsr screen_goto
        ldx #0
-
        lda txt_controls,x
        beq +
        jsr CHROUT
        inx
        bne -
+
        rts

txt_your_hand:
        !text "YOUR HAND:"
        !byte 0

txt_controls:
        !raw "<-> MOVE  SPACE SELECT  P PLAY  D DRAW"
        !byte 0
