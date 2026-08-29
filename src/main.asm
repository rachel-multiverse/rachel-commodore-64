; Rachel C64 - Main Entry Point
; Assembles to a PRG file that loads at $0801
;
; A render-only client for the Rachel card game.
; Connects to iOS host via Zimodem WiFi bridge.

; =============================================================================
; SYMBOL DEFINITIONS (no code, just constants)
; =============================================================================

        !source "src/zeropage.asm"
        !source "src/buffers.asm"
        !source "src/screen_defs.asm"

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

        ; Initialize serial port (User Port, 2400 baud)
        jsr serial_init

        ; Initialize screen (blue background, clear, white text)
        jsr screen_init

        ; Draw the game screen layout
        jsr draw_game_screen

        ; Show "waiting" message in status area
        ldx #1
        ldy #24
        clc
        jsr PLOT
        lda #<txt_waiting
        sta zp_ptr1
        lda #>txt_waiting
        sta zp_ptr1+1
        jsr screen_print

        ; Re-enable interrupts
        cli

        ; Wait for keypress to start
        jsr input_wait_key

        ; Get IP address from user
        jsr input_ip_address
        cmp #0
        beq start               ; Empty input, restart

        ; Attempt connection
        jsr do_connect
        cmp #0
        bne .conn_failed

        ; Wait for game to start
        jsr wait_for_game
        cmp #0
        bne .conn_failed

        ; Game is starting - enter main game loop
        jmp game_loop

.conn_failed:
        ; Show error, wait for key, restart
        jsr input_wait_key
        jmp start

; =============================================================================
; SUBROUTINES
; =============================================================================

        !source "src/screen.asm"
        !source "src/input.asm"
        !source "src/serial.asm"
        !source "src/modem.asm"
        !source "src/rubp.asm"
        !source "src/game.asm"
        !source "src/connect.asm"
        !source "src/loop.asm"

; Clear all buffers to zero
init_buffers:
        ; Clear serial buffers ($C100-$C1FF)
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

        ; Clear application game state ($C200-$C2FF), never KERNAL page $03.
        ldx #0
.clear_game:
        sta $c200,x
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

txt_waiting:
        !text "PRESS ANY KEY TO CONNECT..."
        !byte 0
