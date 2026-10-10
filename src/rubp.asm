; =============================================================================
; RUBP MODULE
; =============================================================================
; Rachel Unified Binary Protocol - 64-byte message handling
;
; Message format (64 bytes total):
;   Header (16 bytes):
;     0-3:   Magic "RACH"
;     4:     Version (0x01)
;     5:     Message type
;     6-7:   Sequence number (big-endian)
;     8-9:   Player ID (big-endian)
;     10-11: Game ID (big-endian)
;     12-15: Timestamp (big-endian, we use 0)
;   Payload (48 bytes): varies by message type

; -----------------------------------------------------------------------------
; Message Types
; -----------------------------------------------------------------------------

MSG_HEARTBEAT   = $00
MSG_HELLO       = $01
MSG_WELCOME     = $02
MSG_GAME_START  = $03
MSG_PLAY_CARD   = $04
MSG_DRAW_CARD   = $05
MSG_CARD_DRAWN  = $06
MSG_GAME_STATE  = $07
MSG_TURN_START  = $08
MSG_TURN_END    = $09
MSG_PLAYER_WON  = $0a
MSG_ERROR       = $0b
MSG_PLAYER_LIST = $0c
MSG_ANNOUNCE    = $0d
MSG_PLAYER_NAME = $0e
MSG_HAND_SYNC   = $0f
MSG_SYNC_REQUEST= $10

; -----------------------------------------------------------------------------
; Header Offsets
; -----------------------------------------------------------------------------

HDR_MAGIC       = 0             ; 4 bytes
HDR_VERSION     = 4             ; 1 byte
HDR_TYPE        = 5             ; 1 byte
HDR_SEQUENCE    = 6             ; 2 bytes (big-endian)
HDR_PLAYER_ID   = 8             ; 2 bytes (big-endian)
HDR_GAME_ID     = 10            ; 2 bytes (big-endian)
HDR_TIMESTAMP   = 12            ; v1: 4 bytes. v2: 2 bytes, then the CRC.
HDR_CRC         = 14            ; v2 only: CRC-16/CCITT-FALSE, big-endian
PAYLOAD_START   = 16            ; Payload begins here

; Transport version. v1 has no integrity field and every byte that arrives is
; believed; v2 spends two header bytes on a CRC so a corrupted frame is dropped
; instead of acted on. On a bit-banged link corruption is the ordinary case,
; not the exception — the VIC-20 client discards between 37 and 74 frames in a
; game it completes cleanly — so v1 is not a safe choice here. The host follows
; whichever version the HELLO header uses, per connection.
RUBP_VERSION    = $02

; -----------------------------------------------------------------------------
; Platform ID (C64 = 0x0002)
; -----------------------------------------------------------------------------

PLATFORM_C64    = $0002

; RachelSpec version this client speaks (negotiated via HELLO/WELCOME).
SPEC_VERSION_HI = $00
SPEC_VERSION_LO = $01

; -----------------------------------------------------------------------------
; Capability bits (HELLO payload+36, echoed in WELCOME payload+8)
; -----------------------------------------------------------------------------

CAP_SYNC_ACK    = $01           ; Host holds TURN_START until we acknowledge

; SYNC_REQUEST flag bits (payload+6)
SYNC_F_HASH     = $01           ; ObservedStateHash is present
SYNC_F_ACK      = $02           ; This is an acknowledgement, not a resync ask

; =============================================================================
; RUBP SUBROUTINES
; =============================================================================

; -----------------------------------------------------------------------------
; Build message header in TX buffer
; Input: A = message type
; Clears TX buffer, writes header with magic, version, seq, player/game IDs
; -----------------------------------------------------------------------------
rubp_build_header:
        sta zp_temp1            ; Save message type

        ; Clear TX buffer
        ldx #0
        lda #0
.hdr_clear:
        sta SERIAL_TX_BUF,x
        inx
        cpx #RUBP_MSG_SIZE
        bne .hdr_clear

        ; Magic bytes "RACH"
        lda #'R'
        sta SERIAL_TX_BUF+HDR_MAGIC
        lda #'A'
        sta SERIAL_TX_BUF+HDR_MAGIC+1
        lda #'C'
        sta SERIAL_TX_BUF+HDR_MAGIC+2
        lda #'H'
        sta SERIAL_TX_BUF+HDR_MAGIC+3

        ; Version
        lda #RUBP_VERSION
        sta SERIAL_TX_BUF+HDR_VERSION

        ; Message type
        lda zp_temp1
        sta SERIAL_TX_BUF+HDR_TYPE

        ; Sequence number (big-endian: high byte first)
        lda zp_sequence+1       ; High byte
        sta SERIAL_TX_BUF+HDR_SEQUENCE
        lda zp_sequence         ; Low byte
        sta SERIAL_TX_BUF+HDR_SEQUENCE+1

        ; Increment sequence for next message
        inc zp_sequence
        bne .no_seq_carry
        inc zp_sequence+1
.no_seq_carry:

        ; Player ID (big-endian)
        lda zp_player_id+1      ; High byte
        sta SERIAL_TX_BUF+HDR_PLAYER_ID
        lda zp_player_id        ; Low byte
        sta SERIAL_TX_BUF+HDR_PLAYER_ID+1

        ; Game ID (big-endian)
        lda zp_game_id+1        ; High byte
        sta SERIAL_TX_BUF+HDR_GAME_ID
        lda zp_game_id          ; Low byte
        sta SERIAL_TX_BUF+HDR_GAME_ID+1

        ; Timestamp = 0 (already cleared)
        rts

; -----------------------------------------------------------------------------
; Send TX buffer as complete 64-byte message
; -----------------------------------------------------------------------------
rubp_send:
        jsr rubp_finalize
        jmp transport_send_frame

; -----------------------------------------------------------------------------
; Stamp the outgoing frame's CRC. Computed over all 64 bytes with the CRC field
; itself zeroed, which is what the receiver reproduces.
; Clobbers: A, X, Y, zp_ptr2
; -----------------------------------------------------------------------------
rubp_finalize:
        lda #0
        sta SERIAL_TX_BUF+HDR_CRC
        sta SERIAL_TX_BUF+HDR_CRC+1
        lda #<SERIAL_TX_BUF
        sta zp_ptr2
        lda #>SERIAL_TX_BUF
        sta zp_ptr2+1
        jsr rubp_crc16
        lda rubp_crc_hi
        sta SERIAL_TX_BUF+HDR_CRC
        lda rubp_crc_lo
        sta SERIAL_TX_BUF+HDR_CRC+1
        rts

; -----------------------------------------------------------------------------
; CRC-16/CCITT-FALSE over the 64-byte frame at zp_ptr2.
; poly $1021, init $FFFF, no reflection, xorout $0000 ("123456789" -> $29B1).
; Out: rubp_crc_hi:rubp_crc_lo. Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
rubp_crc16:
        lda #$ff
        sta rubp_crc_hi
        sta rubp_crc_lo
        ldy #0
.rc_byte:
        lda (zp_ptr2),y
        eor rubp_crc_hi
        sta rubp_crc_hi
        ldx #8
.rc_bit:
        lda rubp_crc_hi
        and #$80
        sta rubp_crc_msb
        asl rubp_crc_lo
        rol rubp_crc_hi
        lda rubp_crc_msb
        beq .rc_no_poly
        lda rubp_crc_lo
        eor #$21
        sta rubp_crc_lo
        lda rubp_crc_hi
        eor #$10
        sta rubp_crc_hi
.rc_no_poly:
        dex
        bne .rc_bit
        iny
        cpy #RUBP_MSG_SIZE
        bne .rc_byte
        rts

rubp_crc_hi:  !byte 0
rubp_crc_lo:  !byte 0
rubp_crc_msb: !byte 0
rubp_rx_crc_hi: !byte 0
rubp_rx_crc_lo: !byte 0

; -----------------------------------------------------------------------------
; Receive 64-byte message into RX buffer (blocking)
; -----------------------------------------------------------------------------
rubp_receive:
        jmp transport_receive_frame

; -----------------------------------------------------------------------------
; Validate RX buffer has valid RUBP header
; Returns: Z=1 if valid (magic = "RACH"), Z=0 if invalid
; -----------------------------------------------------------------------------
rubp_validate:
        lda SERIAL_RX_BUF+HDR_MAGIC
        cmp #'R'
        bne .invalid
        lda SERIAL_RX_BUF+HDR_MAGIC+1
        cmp #'A'
        bne .invalid
        lda SERIAL_RX_BUF+HDR_MAGIC+2
        cmp #'C'
        bne .invalid
        lda SERIAL_RX_BUF+HDR_MAGIC+3
        cmp #'H'
        bne .invalid
        ; Accept either transport version: the host answers in whichever the
        ; HELLO selected, but a lobby may hold both and a stray v1 frame is
        ; better skipped than treated as a framing failure.
        lda SERIAL_RX_BUF+HDR_VERSION
        cmp #$01
        beq .valid              ; v1 carries no integrity field to check
        cmp #$02
        bne .invalid

        ; v2: the CRC is computed over the whole frame with its own two bytes
        ; zeroed, so stash them, recompute, and compare. A frame that fails
        ; here is dropped before its type, identifiers or payload are read —
        ; believing a corrupted GAME_STATE is how a client ends up playing
        ; against a table that never existed.
        lda SERIAL_RX_BUF+HDR_CRC
        sta rubp_rx_crc_hi
        lda SERIAL_RX_BUF+HDR_CRC+1
        sta rubp_rx_crc_lo
        lda #0
        sta SERIAL_RX_BUF+HDR_CRC
        sta SERIAL_RX_BUF+HDR_CRC+1

        lda #<SERIAL_RX_BUF
        sta zp_ptr2
        lda #>SERIAL_RX_BUF
        sta zp_ptr2+1
        jsr rubp_crc16

        ; Put the frame back the way it arrived, whatever the verdict.
        lda rubp_rx_crc_hi
        sta SERIAL_RX_BUF+HDR_CRC
        lda rubp_rx_crc_lo
        sta SERIAL_RX_BUF+HDR_CRC+1

        lda rubp_crc_hi
        cmp rubp_rx_crc_hi
        bne .invalid
        lda rubp_crc_lo
        cmp rubp_rx_crc_lo
        bne .invalid

.valid:
        lda #0                  ; Valid - set Z flag
        rts

.invalid:
        lda #1                  ; Invalid - clear Z flag
        rts

; -----------------------------------------------------------------------------
; Get message type from RX buffer
; Returns: A = message type
; -----------------------------------------------------------------------------
rubp_get_type:
        lda SERIAL_RX_BUF+HDR_TYPE
        rts

; -----------------------------------------------------------------------------
; Build and send HELLO message
; Input: zp_ptr1 = pointer to player name (null-terminated, max 16 chars)
; -----------------------------------------------------------------------------
rubp_send_hello:
        ; Build header
        lda #MSG_HELLO
        jsr rubp_build_header

        ; Copy player name to payload (max 16 chars)
        ldy #0
.copy_name:
        lda (zp_ptr1),y
        beq .name_done
        sta SERIAL_TX_BUF+PAYLOAD_START,y
        iny
        cpy #16
        bne .copy_name
.name_done:

        ; Platform ID at payload+16 (big-endian)
        lda #$00                ; High byte
        sta SERIAL_TX_BUF+PAYLOAD_START+16
        lda #$02                ; Low byte (C64 = 0x0002)
        sta SERIAL_TX_BUF+PAYLOAD_START+17

        ; SpecVersion at payload+18 (big-endian)
        lda #SPEC_VERSION_HI
        sta SERIAL_TX_BUF+PAYLOAD_START+18
        lda #SPEC_VERSION_LO
        sta SERIAL_TX_BUF+PAYLOAD_START+19

        ; Keep the same token across redials. RoomCode remains empty.
        ldx #7
.hello_token:
        lda RECONNECT_TOKEN,x
        sta SERIAL_TX_BUF+PAYLOAD_START+20,x
        dex
        bpl .hello_token

        ; Capabilities at payload+36. Bit 0 asks the host to hold TURN_START
        ; until we acknowledge the GAME_STATE + HAND_SYNC pair. A bit-banged
        ; UART on a machine that also has to draw a screen cannot reliably
        ; catch consecutive 64-byte frames, so this is the difference between
        ; acting on the current table and acting a turn behind.
        lda #CAP_SYNC_ACK
        sta SERIAL_TX_BUF+PAYLOAD_START+36

        ; Send message
        jmp rubp_send

; -----------------------------------------------------------------------------
; Parse WELCOME message from RX buffer
; Extracts: PlayerID, GameID, stores in zero page
; -----------------------------------------------------------------------------
rubp_parse_welcome:
        ; Player ID (big-endian at payload+0,1)
        lda SERIAL_RX_BUF+PAYLOAD_START+1  ; Low byte
        sta zp_player_id
        lda SERIAL_RX_BUF+PAYLOAD_START    ; High byte
        sta zp_player_id+1

        ; Game ID (big-endian at payload+2,3)
        lda SERIAL_RX_BUF+PAYLOAD_START+3  ; Low byte
        sta zp_game_id
        lda SERIAL_RX_BUF+PAYLOAD_START+2  ; High byte
        sta zp_game_id+1

        ; Player count at payload+4
        lda SERIAL_RX_BUF+PAYLOAD_START+4
        sta zp_temp1            ; Store for caller

        ; Capability echo at payload+8. The host repeats our sync-ACK bit only
        ; when it accepted the negotiation, and we must not acknowledge a
        ; handshake it is not running: an ACK flag sent without negotiation is
        ; read as an ordinary resync request, which would fetch the pair again
        ; on every HAND_SYNC.
        lda SERIAL_RX_BUF+PAYLOAD_START+8
        and #CAP_SYNC_ACK
        sta SERVER_SYNC_ACK

        ; Update connection state
        lda #CONN_WAITING
        sta zp_conn_state
        rts

; -----------------------------------------------------------------------------
; Parse GAME_STATE message from RX buffer
; Updates all game state variables
; -----------------------------------------------------------------------------
rubp_parse_game_state:
        ; Current player (payload+0)
        lda SERIAL_RX_BUF+PAYLOAD_START
        sta zp_current_turn

        ; Direction (payload+1)
        lda SERIAL_RX_BUF+PAYLOAD_START+1
        sta DIRECTION

        ; Top card (payload+2)
        lda SERIAL_RX_BUF+PAYLOAD_START+2
        sta DISCARD_TOP

        ; Nominated suit (payload+3)
        lda SERIAL_RX_BUF+PAYLOAD_START+3
        sta NOMINATED_SUIT

        ; Pending draws (payload+4)
        lda SERIAL_RX_BUF+PAYLOAD_START+4
        sta PENDING_DRAWS

        ; Pending skips (payload+5). Declared since the first cut but never
        ; filled in, so nothing could tell a live skip from a quiet turn.
        lda SERIAL_RX_BUF+PAYLOAD_START+5
        sta PENDING_SKIPS

        ; Deck count (payload+6)
        lda SERIAL_RX_BUF+PAYLOAD_START+6
        sta DECK_COUNT

        ; Player card counts (payload+7 to +14)
        ldx #0
.copy_counts:
        lda SERIAL_RX_BUF+PAYLOAD_START+7,x
        sta PLAYER_COUNTS,x
        inx
        cpx #MAX_PLAYERS
        bne .copy_counts

        ; Is game over (payload+15)
        lda SERIAL_RX_BUF+PAYLOAD_START+15
        sta GAME_OVER

        ; Winner index (payload+16)
        lda SERIAL_RX_BUF+PAYLOAD_START+16
        sta WINNER_INDEX

        ; Capture the state hash if present (Flags bit0 at payload+23, hash at
        ; payload+24..31). We echo it back as ObservedStateHash when we act.
        lda SERIAL_RX_BUF+PAYLOAD_START+23
        and #$01
        beq .gs_no_hash
        ldx #0
.gs_copy_hash:
        lda SERIAL_RX_BUF+PAYLOAD_START+24,x
        sta OBSERVED_HASH,x
        inx
        cpx #8
        bne .gs_copy_hash
        lda #1
        sta HASH_VALID

        ; The turn number (payload+17) and spec version (payload+21) belong to
        ; this same message, so an acknowledgement describes one snapshot. Both
        ; are copied big-endian exactly as received, to be echoed unaltered.
        ldx #0
.gs_copy_turn:
        lda SERIAL_RX_BUF+PAYLOAD_START+17,x
        sta OBSERVED_TURN,x
        inx
        cpx #4
        bne .gs_copy_turn

        lda SERIAL_RX_BUF+PAYLOAD_START+21
        sta OBSERVED_SPEC
        lda SERIAL_RX_BUF+PAYLOAD_START+22
        sta OBSERVED_SPEC+1

        ; This message is what makes an acknowledgement honest: it is the one
        ; we actually parsed. Nothing else sets the flag.
        lda #1
        sta GAME_STATE_FRESH
        jmp .gs_done
.gs_no_hash:
        lda #0
        sta HASH_VALID
.gs_done:
        rts

; -----------------------------------------------------------------------------
; Parse GAME_START or CARD_DRAWN message (both have same format)
; Input: A = 0 for replace (GAME_START), A = 1 for append (CARD_DRAWN)
; -----------------------------------------------------------------------------
rubp_parse_cards:
        sta zp_temp1            ; Save mode

        ; Card count at payload+0
        lda SERIAL_RX_BUF+PAYLOAD_START
        sta zp_temp2            ; Number of cards

        ; Get starting index in hand
        lda zp_temp1
        bne .append_mode
        ; Replace mode - start at 0
        lda #0
        sta zp_hand_count
        beq .start_copy

.append_mode:
        ; Append mode - start at current count

.start_copy:
        ldx zp_hand_count       ; Destination index
        ldy #0                  ; Source index

.copy_cards:
        cpy zp_temp2
        beq .copy_done
        cpx #MAX_HAND_SIZE
        beq .copy_done
        lda SERIAL_RX_BUF+PAYLOAD_START+1,y  ; Cards start at payload+1
        sta MY_HAND,x
        inx
        iny
        jmp .copy_cards

.copy_done:
        stx zp_hand_count       ; Update hand count
        ; A replacement can remove the card under the cursor. Match the solo
        ; publisher: preserve valid positions and reset removed ones to zero.
        lda zp_cursor_pos
        cmp zp_hand_count
        bcc .cursor_valid
        lda #0
        sta zp_cursor_pos
.cursor_valid:
        rts

; Convenience wrappers
rubp_parse_game_start:
        lda #0                  ; Replace mode
        jmp rubp_parse_cards

rubp_parse_card_drawn:
        lda #1                  ; Append mode
        jmp rubp_parse_cards

; -----------------------------------------------------------------------------
; Build and send PLAY_CARD message
; Plays cards marked in the 32-byte selection table
; Input: zp_temp2 = nominated suit ($FF if none)
; -----------------------------------------------------------------------------
rubp_send_play_card:
        ; Build header
        lda #MSG_PLAY_CARD
        jsr rubp_build_header

        ; Count selected cards and copy to payload
        ldx #0                  ; Source index in hand
        ldy #0                  ; Dest index in payload (cards at +1)
.check_loop:
        cpx zp_hand_count
        beq .count_done

        lda SELECTED_CARDS,x
        beq .not_selected

        ; Card is selected - copy it
        lda MY_HAND,x
        sta SERIAL_TX_BUF+PAYLOAD_START+1,y
        iny

.not_selected:
.next_card:
        inx
        bne .check_loop

.count_done:
        ; Store card count at payload+0
        tya
        sta SERIAL_TX_BUF+PAYLOAD_START

        ; Nominated suit at payload+33
        lda zp_temp2
        sta SERIAL_TX_BUF+PAYLOAD_START+33

        ; SpecVersion at payload+34 (big-endian)
        lda #SPEC_VERSION_HI
        sta SERIAL_TX_BUF+PAYLOAD_START+34
        lda #SPEC_VERSION_LO
        sta SERIAL_TX_BUF+PAYLOAD_START+35

        ; Flags at payload+36, ObservedStateHash at payload+37..44
        ldx #36
        jsr write_obs_hash

        ; Send
        jmp rubp_send

; -----------------------------------------------------------------------------
; Build and send DRAW_CARD message
; Input: A = reason (0=can't play, 1=attack penalty)
; -----------------------------------------------------------------------------
rubp_send_draw_card:
        sta zp_temp2            ; Save reason (NOT temp1: build_header clobbers
                                ; temp1 with the message type)

        ; Build header
        lda #MSG_DRAW_CARD
        jsr rubp_build_header

        ; Reason at payload+0
        lda zp_temp2
        sta SERIAL_TX_BUF+PAYLOAD_START

        ; Count at payload+1 (always 1 for manual draw)
        lda #1
        sta SERIAL_TX_BUF+PAYLOAD_START+1

        ; SpecVersion at payload+2 (big-endian)
        lda #SPEC_VERSION_HI
        sta SERIAL_TX_BUF+PAYLOAD_START+2
        lda #SPEC_VERSION_LO
        sta SERIAL_TX_BUF+PAYLOAD_START+3

        ; Flags at payload+4, ObservedStateHash at payload+5..12
        ldx #4
        jsr write_obs_hash

        ; Send
        jmp rubp_send

; -----------------------------------------------------------------------------
; -----------------------------------------------------------------------------
; Send SYNC_REQUEST. Liveness and error recovery always ask for a fresh pair;
; they cannot acknowledge a public GAME_STATE without its private HAND_SYNC.
;
; A host that accepted CAP_SYNC_ACK will not send TURN_START until an
; acknowledgement arrives whose hash matches the pair it sent. That only works
; if the acknowledgement means what the host assumes, so it must describe a
; snapshot this client actually parsed.
;
; The trap the VIC-20 client fell into: the state hash rides on GAME_STATE,
; HAND_SYNC and TURN_START alike. Keep one hash variable, let every handler
; write it, and acknowledge on HAND_SYNC, and a discarded GAME_STATE is still
; certified — you return a perfectly current hash for a view you never saw, the
; host releases TURN_START, and you act a turn behind on whichever fields only
; GAME_STATE carries (the top discard above all). Here GAME_STATE is the sole
; writer of OBSERVED_HASH / OBSERVED_TURN / OBSERVED_SPEC, and GAME_STATE_FRESH
; says one arrived and has not been acknowledged yet. An ACK additionally
; requires a HAND_SYNC with matching turn, spec version and state hash.
;
; Without that flag we send a plain resync request instead: the host answers by
; resending the pair, which costs one round trip rather than a wrong turn. Frame
; loss is the ordinary condition of a bit-banged UART, not an edge case.
;
; See protocol/CLIENT_GUIDE.md, "Acknowledge what you received, not what you
; were told", and specs/rachel-sync-v1.md.
; Clobbers: A, X, Y
; -----------------------------------------------------------------------------
rubp_send_sync_request:
        jsr rubp_build_sync_request
        jmp rubp_send

; Called only after parsing HAND_SYNC. A missing/mismatched half requests a new
; pair without consuming the fresh public state or claiming it is complete.
rubp_send_sync_ack:
        jsr rubp_hand_matches_state
        beq .sa_matched
        jmp rubp_send_sync_request
.sa_matched:
        jsr rubp_build_sync_request
        lda SERIAL_TX_BUF+PAYLOAD_START+6
        ora #SYNC_F_ACK
        sta SERIAL_TX_BUF+PAYLOAD_START+6
        lda #0
        sta GAME_STATE_FRESH
        jmp rubp_send

; A=0 only for an unacknowledged state and the same private snapshot in RX.
; Reconnect uses this before replacing the hand or resuming input.
rubp_hand_matches_state:
        lda GAME_STATE_FRESH
        beq .hm_mismatch
        lda HASH_VALID
        beq .hm_mismatch
        lda SERIAL_RX_BUF+HDR_TYPE
        cmp #MSG_HAND_SYNC
        bne .hm_mismatch
        lda SERIAL_RX_BUF+PAYLOAD_START+39
        and #SYNC_F_HASH
        beq .hm_mismatch
        ldx #3
.hm_turn:
        lda SERIAL_RX_BUF+PAYLOAD_START+33,x
        cmp OBSERVED_TURN,x
        bne .hm_mismatch
        dex
        bpl .hm_turn
        ldx #1
.hm_spec:
        lda SERIAL_RX_BUF+PAYLOAD_START+37,x
        cmp OBSERVED_SPEC,x
        bne .hm_mismatch
        dex
        bpl .hm_spec
        ldx #7
.hm_hash:
        lda SERIAL_RX_BUF+PAYLOAD_START+40,x
        cmp OBSERVED_HASH,x
        bne .hm_mismatch
        dex
        bpl .hm_hash
        lda #0
        rts
.hm_mismatch:
        lda #1
        rts

rubp_build_sync_request:
        lda #MSG_SYNC_REQUEST
        jsr rubp_build_header

        ; TurnNumber (payload+0..3), big-endian exactly as received.
        ldx #0
.sr_turn:
        lda OBSERVED_TURN,x
        sta SERIAL_TX_BUF+PAYLOAD_START,x
        inx
        cpx #4
        bne .sr_turn

        ; SpecVersion (payload+4,5), likewise echoed rather than assumed.
        lda OBSERVED_SPEC
        sta SERIAL_TX_BUF+PAYLOAD_START+4
        lda OBSERVED_SPEC+1
        sta SERIAL_TX_BUF+PAYLOAD_START+5

        ; Flags at payload+6, ObservedStateHash at payload+7..14.
        ldx #6
        jsr write_obs_hash

        rts

; -----------------------------------------------------------------------------
; Write the Flags byte + ObservedStateHash into the TX payload.
; Input: X = payload offset of the Flags byte; the 8-byte hash follows at X+1..X+8
; If no state hash has been captured yet, the (already-cleared) flag and hash
; bytes are left at zero — i.e. Flags bit0 = 0, "no hash present".
; Clobbers: A, X, Y
; -----------------------------------------------------------------------------
write_obs_hash:
        lda HASH_VALID
        beq .woh_done

        lda #SYNC_F_HASH        ; Flags bit0 = ObservedStateHash present
        sta SERIAL_TX_BUF+PAYLOAD_START,x

        ldy #0
.woh_copy:
        inx
        lda OBSERVED_HASH,y
        sta SERIAL_TX_BUF+PAYLOAD_START,x
        iny
        cpy #8
        bne .woh_copy

.woh_done:
        rts
