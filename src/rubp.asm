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

; -----------------------------------------------------------------------------
; Header Offsets
; -----------------------------------------------------------------------------

HDR_MAGIC       = 0             ; 4 bytes
HDR_VERSION     = 4             ; 1 byte
HDR_TYPE        = 5             ; 1 byte
HDR_SEQUENCE    = 6             ; 2 bytes (big-endian)
HDR_PLAYER_ID   = 8             ; 2 bytes (big-endian)
HDR_GAME_ID     = 10            ; 2 bytes (big-endian)
HDR_TIMESTAMP   = 12            ; 4 bytes (big-endian)
PAYLOAD_START   = 16            ; Payload begins here

; -----------------------------------------------------------------------------
; Platform ID (C64 = 0x0002)
; -----------------------------------------------------------------------------

PLATFORM_C64    = $0002

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
        lda #$01
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
        ldx #0
.tx_loop:
        lda SERIAL_TX_BUF,x
        jsr serial_send_byte
        inx
        cpx #RUBP_MSG_SIZE
        bne .tx_loop
        rts

; -----------------------------------------------------------------------------
; Receive 64-byte message into RX buffer (blocking)
; -----------------------------------------------------------------------------
rubp_receive:
        ldx #0
.rx_loop:
        jsr serial_recv_byte
        sta SERIAL_RX_BUF,x
        inx
        cpx #RUBP_MSG_SIZE
        bne .rx_loop
        rts

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
        lda SERIAL_RX_BUF+PAYLOAD_START+1,y  ; Cards start at payload+1
        sta MY_HAND,x
        inx
        iny
        cpx #MAX_HAND_SIZE
        bne .copy_cards

.copy_done:
        stx zp_hand_count       ; Update hand count
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
; Plays cards marked in selection bitmask
; Input: zp_temp2 = nominated suit ($FF if none)
; -----------------------------------------------------------------------------
rubp_send_play_card:
        ; Build header
        lda #MSG_PLAY_CARD
        jsr rubp_build_header

        ; Count selected cards and copy to payload
        ldx #0                  ; Source index in hand
        ldy #0                  ; Dest index in payload (cards at +1)
        lda #1                  ; Bit mask for selection

.check_loop:
        cpx zp_hand_count
        beq .count_done

        pha                     ; Save bit mask
        and zp_selected_lo      ; Check if selected (first 8 cards)
        beq .not_selected

        ; Card is selected - copy it
        lda MY_HAND,x
        sta SERIAL_TX_BUF+PAYLOAD_START+1,y
        iny

.not_selected:
        pla                     ; Restore mask
        asl                     ; Next bit
        bne .next_card
        lda #1                  ; Wrap (shouldn't happen with <8 selected)
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

        ; Send
        jmp rubp_send
