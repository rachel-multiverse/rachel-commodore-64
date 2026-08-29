; =============================================================================
; RUBP DECODER CONFORMANCE HARNESS
; =============================================================================
; Drives the REAL client parsers from src/rubp.asm with the golden fixture
; vectors (loaded into SERIAL_RX_BUF) and captures the variables they extract,
; so the host can check the parser pulled the right value from the right offset.
;
; Input vectors come from build/vectors.inc, which run.py regenerates from
; rubp-messages-v1.json each run — so the bytes fed in are always the golden
; bytes, with no hand-transcription drift.
;
; Capture layout (free RAM at $C000):
;   WELCOME    ($C000): playerID lo/hi, gameID lo/hi, playerCount, connState
;   GAME_STATE ($C010): currentTurn, direction, topCard, nominatedSuit,
;                       pendingDraws, deckCount, playerCounts[8], gameOver,
;                       winnerIndex, observedHash[8], hashValid
;   $C0FF      done marker = $AA
;
; Build: asm198x --dialect acme --prg -I .. -I . decoders.asm -o build/decoders.prg

        !source "../src/zeropage.asm"
        !source "../src/buffers.asm"

DCAP_WELCOME = $c000
DCAP_GS      = $c010
DCAP_DONE    = $c0ff

        * = $0801
        !byte $0c, $08
        !byte $0a, $00
        !byte $9e
        !text "2064"
        !byte $00
        !byte $00, $00

        * = $0810
start:
        sei

        jsr test_welcome
        jsr test_game_state

        lda #$aa
        sta DCAP_DONE
done:
        jmp done

; -----------------------------------------------------------------------------
; WELCOME: parse the golden welcome vector, capture what it extracts.
; -----------------------------------------------------------------------------
test_welcome:
        lda #<welcome_msg
        sta zp_ptr1
        lda #>welcome_msg
        sta zp_ptr1+1
        jsr load_rx

        jsr rubp_parse_welcome

        lda zp_player_id
        sta DCAP_WELCOME+0
        lda zp_player_id+1
        sta DCAP_WELCOME+1
        lda zp_game_id
        sta DCAP_WELCOME+2
        lda zp_game_id+1
        sta DCAP_WELCOME+3
        lda zp_temp1            ; player count (parse_welcome leaves it here)
        sta DCAP_WELCOME+4
        lda zp_conn_state
        sta DCAP_WELCOME+5
        rts

; -----------------------------------------------------------------------------
; GAME_STATE: clear the hash state first so we prove the parser sets it, then
; parse the golden vector and capture everything it extracts.
; -----------------------------------------------------------------------------
test_game_state:
        lda #0
        sta HASH_VALID
        ldx #0
.dclr:
        sta OBSERVED_HASH,x
        inx
        cpx #8
        bne .dclr

        lda #<game_state_msg
        sta zp_ptr1
        lda #>game_state_msg
        sta zp_ptr1+1
        jsr load_rx

        jsr rubp_parse_game_state

        lda zp_current_turn
        sta DCAP_GS+0
        lda DIRECTION
        sta DCAP_GS+1
        lda DISCARD_TOP
        sta DCAP_GS+2
        lda NOMINATED_SUIT
        sta DCAP_GS+3
        lda PENDING_DRAWS
        sta DCAP_GS+4
        lda DECK_COUNT
        sta DCAP_GS+5
        ldx #0
.dcounts:
        lda PLAYER_COUNTS,x
        sta DCAP_GS+6,x
        inx
        cpx #MAX_PLAYERS
        bne .dcounts            ; DCAP_GS+6 .. +13
        lda GAME_OVER
        sta DCAP_GS+14
        lda WINNER_INDEX
        sta DCAP_GS+15
        ldx #0
.dhash:
        lda OBSERVED_HASH,x
        sta DCAP_GS+16,x
        inx
        cpx #8
        bne .dhash              ; DCAP_GS+16 .. +23
        lda HASH_VALID
        sta DCAP_GS+24
        rts

; -----------------------------------------------------------------------------
; Copy 64 bytes from (zp_ptr1) into SERIAL_RX_BUF.
; -----------------------------------------------------------------------------
load_rx:
        ldy #0
.lrx:
        lda (zp_ptr1),y
        sta SERIAL_RX_BUF,y
        iny
        cpy #RUBP_MSG_SIZE
        bne .lrx
        rts

; -----------------------------------------------------------------------------
; Serial stubs (unused by the parsers, but rubp.asm references them).
; -----------------------------------------------------------------------------
serial_send_byte:
        rts
serial_recv_byte:
        lda #0
        rts

        !source "build/vectors.inc"
        !source "../src/rubp.asm"
