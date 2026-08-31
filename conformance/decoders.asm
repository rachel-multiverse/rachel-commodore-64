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
;   SYNC_ACK   ($C030): flags, turnNumber[4], specVersion[2], stateHash[8]
;   $C0FF      done marker = $AA
;
; Build: asm198x --dialect acme --prg -I .. -I . decoders.asm -o build/decoders.prg

        !source "../src/zeropage.asm"
        !source "../src/buffers.asm"

DCAP_WELCOME = $c000
DCAP_GS      = $c010
DCAP_SYNC    = $c030
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
        jsr test_sync_ack

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
; SYNC ACK: the acknowledgement must describe the GAME_STATE we actually parsed.
;
; GAME_STATE and HAND_SYNC both carry a state hash, and the golden fixtures
; deliberately carry different ones (GAME_STATE $ABC..., HAND_SYNC $1111...).
; Feeding the pair in order and then acknowledging proves the client echoes
; GAME_STATE's snapshot rather than whichever message arrived last.
;
; A client that lets HAND_SYNC overwrite the hash returns a perfectly current
; value for a view it may never have received. The host takes it at its word,
; releases TURN_START, and the client acts a turn behind on the fields only
; GAME_STATE carries — the top discard above all. That is the bug the VIC-20
; client shipped with; it fired seven to nine times per ten-play game.
; -----------------------------------------------------------------------------
test_sync_ack:
        lda #<game_state_msg
        sta zp_ptr1
        lda #>game_state_msg
        sta zp_ptr1+1
        jsr load_rx
        jsr rubp_parse_game_state

        ; HAND_SYNC completes the pair. Its own turn number and hash must not
        ; displace the ones we are about to acknowledge.
        lda #<hand_sync_msg
        sta zp_ptr1
        lda #>hand_sync_msg
        sta zp_ptr1+1
        jsr load_rx
        jsr rubp_parse_game_start

        jsr rubp_send_sync_request

        lda SERIAL_TX_BUF+PAYLOAD_START+6       ; Flags
        sta DCAP_SYNC+0

        ldx #0
.sa_meta:
        lda SERIAL_TX_BUF+PAYLOAD_START,x       ; TurnNumber[4] + SpecVersion[2]
        sta DCAP_SYNC+1,x
        inx
        cpx #6
        bne .sa_meta

        ldy #0
.sa_hash:
        lda SERIAL_TX_BUF+PAYLOAD_START+7,y     ; ObservedStateHash[8]
        sta DCAP_SYNC+7,y
        iny
        cpy #8
        bne .sa_hash
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
; Transport stubs (unused by the parsers, but rubp.asm references them).
; -----------------------------------------------------------------------------
transport_send_frame:
        rts
transport_receive_frame:
        lda #0
        rts

        !source "build/vectors.inc"
        !source "../src/rubp.asm"
