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
DCAP_PAIRS   = $c040
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
        jsr test_pair_checks

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
; Mismatched fixtures must ask for a coherent pair, never acknowledge one.
;
; GAME_STATE and HAND_SYNC both carry a state hash, and the golden fixtures
; deliberately carry different ones (GAME_STATE $ABC..., HAND_SYNC $1111...).
; The request still echoes GAME_STATE's snapshot instead of letting HAND_SYNC
; overwrite public state that it never carried.
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

        ; This HAND_SYNC does not match the GAME_STATE above.
        lda #<hand_sync_msg
        sta zp_ptr1
        lda #>hand_sync_msg
        sta zp_ptr1+1
        jsr load_rx
        jsr rubp_parse_game_start

        jsr rubp_send_sync_ack

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

; Public-only updates occur whenever two other seats take successive turns.
; Watchdog requests must not turn that public half into a completed pair.
test_pair_checks:
        jsr load_public_state
        jsr rubp_send_sync_request
        lda SERIAL_TX_BUF+PAYLOAD_START+6
        sta DCAP_PAIRS
        jsr rubp_send_sync_ack
        lda SERIAL_TX_BUF+PAYLOAD_START+6
        sta DCAP_PAIRS+1

        jsr load_matching_pair
        jsr rubp_parse_game_start
        jsr rubp_send_sync_ack
        lda SERIAL_TX_BUF+PAYLOAD_START+6
        sta DCAP_PAIRS+2
        jsr rubp_send_sync_ack
        lda SERIAL_TX_BUF+PAYLOAD_START+6
        sta DCAP_PAIRS+3

        jsr load_public_state
        inc SERIAL_RX_BUF+PAYLOAD_START+20
        jsr rubp_parse_game_state
        jsr rubp_send_sync_request
        lda SERIAL_TX_BUF+PAYLOAD_START+6
        sta DCAP_PAIRS+4

        jsr load_matching_pair
        lda #0
        sta SERIAL_RX_BUF+PAYLOAD_START+39
        jsr rubp_send_sync_ack
        lda SERIAL_TX_BUF+PAYLOAD_START+6
        sta DCAP_PAIRS+5

        jsr load_public_state
        lda #0
        sta SERIAL_RX_BUF+PAYLOAD_START+23
        jsr rubp_parse_game_state
        jsr load_matching_hand
        jsr rubp_send_sync_ack
        lda SERIAL_TX_BUF+PAYLOAD_START+6
        sta DCAP_PAIRS+6

        lda #0
        sta GAME_STATE_FRESH
        sta HASH_VALID
        jsr load_matching_hand
        jsr rubp_send_sync_ack
        lda SERIAL_TX_BUF+PAYLOAD_START+6
        sta DCAP_PAIRS+7

        lda #0
        sta pair_field_index
.pc_field:
        jsr load_matching_pair
        ldx pair_field_index
        ldy pair_field_offsets,x
        lda SERIAL_RX_BUF+PAYLOAD_START,y
        eor #1
        sta SERIAL_RX_BUF+PAYLOAD_START,y
        jsr rubp_send_sync_ack
        ldx pair_field_index
        lda SERIAL_TX_BUF+PAYLOAD_START+6
        sta DCAP_PAIRS+8,x
        inc pair_field_index
        lda pair_field_index
        cmp #14
        bne .pc_field
        rts

pair_field_index: !byte 0
pair_field_offsets: !byte 33,34,35,36,37,38,40,41,42,43,44,45,46,47

load_public_state:
        lda #<game_state_msg
        sta zp_ptr1
        lda #>game_state_msg
        sta zp_ptr1+1
        jsr load_rx
        jmp rubp_parse_game_state

load_matching_pair:
        jsr load_public_state
load_matching_hand:
        lda #<hand_sync_msg
        sta zp_ptr1
        lda #>hand_sync_msg
        sta zp_ptr1+1
        jsr load_rx
        ; Same private cards, but metadata from the public golden vector.
        ; The unmodified canonical HAND_SYNC above deliberately differs.
        ldx #5
.mh_meta:
        lda game_state_msg+PAYLOAD_START+17,x
        sta SERIAL_RX_BUF+PAYLOAD_START+33,x
        dex
        bpl .mh_meta
        ldx #7
.mh_hash:
        lda game_state_msg+PAYLOAD_START+24,x
        sta SERIAL_RX_BUF+PAYLOAD_START+40,x
        dex
        bpl .mh_hash
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
