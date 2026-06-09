; =============================================================================
; RUBP ENCODER CONFORMANCE HARNESS
; =============================================================================
; Drives the REAL client encoders from src/rubp.asm with the field values from
; the golden fixtures (docs specs/fixtures/rubp-messages-v1.json) and leaves each
; 64-byte result in a capture region for the host to read back and diff.
;
; The encoders build into SERIAL_TX_BUF and then `jmp rubp_send`, which streams
; the buffer out one byte at a time via serial_send_byte. We stub that (and
; serial_recv_byte) to RTS so nothing touches the User Port — the built message
; still sits in SERIAL_TX_BUF, which is what we capture.
;
; Capture layout (free RAM at $C000):
;   $C000-$C03F  HELLO      (fixture "hello",      seq 0x0021)
;   $C040-$C07F  PLAY_CARD  (fixture "play_card",  seq 0x0022)
;   $C080-$C0BF  DRAW_CARD  (fixture "draw_card",  seq 0x0023)
;   $C0FF        done marker = $AA once every test has run
;
; Build:  acme -f cbm -o build/encoders.prg encoders.asm   (run from this dir)

        !source "../src/zeropage.asm"
        !source "../src/buffers.asm"

CAP_HELLO     = $c000
CAP_PLAY      = $c040
CAP_DRAW      = $c080
CAP_DONE      = $c0ff

; -----------------------------------------------------------------------------
; BASIC stub: 10 SYS 2064
; -----------------------------------------------------------------------------
        * = $0801
        !byte $0c, $08          ; pointer to next BASIC line
        !byte $0a, $00          ; line number 10
        !byte $9e               ; SYS token
        !text "2064"            ; address
        !byte $00               ; end of line
        !byte $00, $00          ; end of program

; -----------------------------------------------------------------------------
; Entry
; -----------------------------------------------------------------------------
        * = $0810
start:
        sei

        jsr test_hello
        jsr test_play_card
        jsr test_draw_card

        lda #$aa                ; signal "all tests ran" to the host
        sta CAP_DONE
done:
        jmp done

; -----------------------------------------------------------------------------
; HELLO: name "Alice", seq 0x0021, playerID 0xFFFF, gameID 0x0042
; (platform is hardcoded 0x0002 by the client; the fixture used iOS 0x0031)
; -----------------------------------------------------------------------------
test_hello:
        lda #$21                ; sequence 0x0021 (lo, hi)
        sta zp_sequence
        lda #$00
        sta zp_sequence+1
        lda #$ff                ; playerID 0xFFFF (lo, hi)
        sta zp_player_id
        sta zp_player_id+1
        lda #$42                ; gameID 0x0042 (lo, hi)
        sta zp_game_id
        lda #$00
        sta zp_game_id+1

        lda #<name_alice        ; name pointer
        sta zp_ptr1
        lda #>name_alice
        sta zp_ptr1+1

        jsr rubp_send_hello

        lda #<CAP_HELLO
        sta zp_ptr2
        lda #>CAP_HELLO
        sta zp_ptr2+1
        jmp capture_tx

; -----------------------------------------------------------------------------
; PLAY_CARD: one card A♥ (0x0E), nominated suit clubs (0x02),
; seq 0x0022, playerID 0x0001, gameID 0x0042
; -----------------------------------------------------------------------------
test_play_card:
        lda #$22                ; sequence 0x0022
        sta zp_sequence
        lda #$00
        sta zp_sequence+1
        lda #$01                ; playerID 0x0001
        sta zp_player_id
        lda #$00
        sta zp_player_id+1
        lda #$42                ; gameID 0x0042
        sta zp_game_id
        lda #$00
        sta zp_game_id+1

        lda #$0e                ; hand: one card, A♥
        sta MY_HAND
        lda #1
        sta zp_hand_count
        lda #$01                ; select card 0 (bit 0)
        sta zp_selected_lo
        lda #$02                ; nominated suit = clubs
        sta zp_temp2

        lda #<hash_play         ; observed state hash (as if captured from GAME_STATE)
        sta zp_ptr1
        lda #>hash_play
        sta zp_ptr1+1
        jsr load_obs_hash

        jsr rubp_send_play_card

        lda #<CAP_PLAY
        sta zp_ptr2
        lda #>CAP_PLAY
        sta zp_ptr2+1
        jmp capture_tx

; -----------------------------------------------------------------------------
; DRAW_CARD: reason 0 (CANNOT_PLAY), seq 0x0023, playerID 0x0001, gameID 0x0042
; -----------------------------------------------------------------------------
test_draw_card:
        lda #$23                ; sequence 0x0023
        sta zp_sequence
        lda #$00
        sta zp_sequence+1
        lda #$01                ; playerID 0x0001
        sta zp_player_id
        lda #$00
        sta zp_player_id+1
        lda #$42                ; gameID 0x0042
        sta zp_game_id
        lda #$00
        sta zp_game_id+1

        lda #<hash_draw         ; observed state hash (as if captured from GAME_STATE)
        sta zp_ptr1
        lda #>hash_draw
        sta zp_ptr1+1
        jsr load_obs_hash

        lda #$00                ; reason = CANNOT_PLAY
        jsr rubp_send_draw_card

        lda #<CAP_DRAW
        sta zp_ptr2
        lda #>CAP_DRAW
        sta zp_ptr2+1
        jmp capture_tx

; -----------------------------------------------------------------------------
; Copy the 64-byte SERIAL_TX_BUF to (zp_ptr2)
; -----------------------------------------------------------------------------
capture_tx:
        ldy #0
.loop:
        lda SERIAL_TX_BUF,y
        sta (zp_ptr2),y
        iny
        cpy #RUBP_MSG_SIZE
        bne .loop
        rts

; -----------------------------------------------------------------------------
; Load an 8-byte observed state hash from (zp_ptr1) and mark it valid — stands
; in for parse_game_state having captured it from a GAME_STATE broadcast.
; -----------------------------------------------------------------------------
load_obs_hash:
        ldy #0
.lh_loop:
        lda (zp_ptr1),y
        sta OBSERVED_HASH,y
        iny
        cpy #8
        bne .lh_loop
        lda #1
        sta HASH_VALID
        rts

; -----------------------------------------------------------------------------
; Serial stubs — the encoders call these; we don't want real User Port I/O.
; -----------------------------------------------------------------------------
serial_send_byte:
        rts
serial_recv_byte:
        lda #0
        rts

name_alice:
        !text "Alice"
        !byte 0

; Observed-state-hash inputs matching the golden play_card / draw_card fixtures.
hash_play:
        !byte $11, $22, $33, $44, $55, $66, $77, $88
hash_draw:
        !byte $88, $77, $66, $55, $44, $33, $22, $11

; -----------------------------------------------------------------------------
; The real client codec under test
; -----------------------------------------------------------------------------
        !source "../src/rubp.asm"
