; Rachel C64 - Main Entry Point
; Assembles to a PRG file that loads at $0801
;
; A render-only client for the Rachel card game.
; Connects to iOS host via Zimodem WiFi bridge.

; =============================================================================
; INCLUDES
; =============================================================================

        !source "src/zeropage.asm"
        !source "src/buffers.asm"

; =============================================================================
; PROGRAM START
; =============================================================================

        * = $0801

; =============================================================================
; BASIC STUB
; =============================================================================
; Creates: 10 SYS 2064
; This allows the program to be loaded and run with LOAD"*",8,1 then RUN

basic_stub:
        !byte $0c, $08          ; Pointer to next BASIC line ($080C)
        !byte $0a, $00          ; Line number 10
        !byte $9e               ; SYS token
        !text "2064"            ; Address as ASCII digits
        !byte $00               ; End of BASIC line
        !byte $00, $00          ; End of BASIC program (null pointer)

; =============================================================================
; PROGRAM ENTRY POINT
; =============================================================================
; Entry at $0810 (2064 decimal) - where SYS jumps to

        * = $0810

start:
        ; Disable interrupts during setup
        sei

        ; Initialize all buffers
        jsr init_buffers

        ; Set border and background to blue
        lda #6                  ; Blue
        sta $d020               ; Border color
        sta $d021               ; Background color

        ; Clear screen (PETSCII code $93)
        lda #$93
        jsr $ffd2               ; KERNAL CHROUT

        ; Set text color to white
        lda #1                  ; White
        sta $0286               ; Current text color

        ; Print title
        ldx #0
.print_title:
        lda title_text,x
        beq .title_done
        jsr $ffd2               ; KERNAL CHROUT
        inx
        bne .print_title
.title_done:

        ; Re-enable interrupts
        cli

        ; Infinite loop (placeholder for main loop)
.idle:
        jmp .idle

; =============================================================================
; SUBROUTINES
; =============================================================================

; Clear all buffers to zero
init_buffers:
        ; Clear serial buffers ($0200-$02FF)
        lda #0
        ldx #0
.clear_serial:
        sta SERIAL_RX_BUF,x
        sta SERIAL_TX_BUF,x
        sta AT_CMD_BUF,x
        sta AT_RESP_BUF,x
        inx
        cpx #64
        bne .clear_serial

        ; Clear game state ($0300-$03FF)
        ldx #0
.clear_game:
        sta $0300,x
        inx
        bne .clear_game         ; Clears full 256 bytes

        ; Initialize zero page buffer pointers
        sta zp_rx_head
        sta zp_rx_tail
        sta zp_tx_head
        sta zp_tx_tail

        ; Initialize game state
        sta zp_hand_count
        sta zp_cursor_pos
        sta zp_selected_lo
        sta zp_selected_hi
        sta zp_conn_state       ; CONN_DISCONNECTED

        ; Initialize sequence counter to 1
        lda #1
        sta zp_sequence
        lda #0
        sta zp_sequence+1

        rts

; =============================================================================
; DATA
; =============================================================================

title_text:
        ; Center the title (40 cols - 15 chars = 25, /2 = 12 spaces)
        !text "            "
        !text "RACHEL C64 V1.0"
        !byte $0d               ; Carriage return
        !byte $0d
        !text "       "
        !text "CONNECTING TO HOST..."
        !byte $0d
        !byte $00               ; Null terminator
