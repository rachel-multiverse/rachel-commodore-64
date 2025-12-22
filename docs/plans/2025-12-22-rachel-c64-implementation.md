# Rachel C64 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a working Rachel card game client for Commodore 64 in 6502 assembly.

**Architecture:** Render-only client connecting to iOS host via Zimodem WiFi bridge. ACME assembler, PETSCII display, User Port serial at 2400 baud.

**Tech Stack:** ACME assembler, VICE emulator, 6502 assembly, RUBP protocol

---

## Task 1: Bootstrap - Minimal PRG that runs

**Files:**
- Create: `src/main.asm`

**Step 1: Create minimal C64 program**

```asm
; Rachel C64 - Main Entry Point
; Assembles to a PRG file that loads at $0801

        * = $0801

; BASIC stub: 10 SYS 2064
        !byte $0c, $08          ; Next line pointer
        !byte $0a, $00          ; Line number 10
        !byte $9e               ; SYS token
        !text "2064"            ; Address as ASCII
        !byte $00               ; End of line
        !byte $00, $00          ; End of BASIC program

; Entry point at $0810
        * = $0810

start:
        ; Clear screen
        lda #$93                ; Clear screen PETSCII
        jsr $ffd2               ; CHROUT

        ; Print hello message
        ldx #0
.loop:
        lda message,x
        beq .done
        jsr $ffd2
        inx
        bne .loop
.done:
        ; Infinite loop
        jmp .done

message:
        !text "RACHEL C64 V1.0"
        !byte $0d               ; Carriage return
        !text "LOADING..."
        !byte $00
```

**Step 2: Build and verify**

Run: `make`
Expected: `build/rachel.prg` created without errors

**Step 3: Test in VICE**

Run: `make run`
Expected: Screen clears, displays "RACHEL C64 V1.0" and "LOADING..."

**Step 4: Commit**

```bash
git add src/main.asm
git commit -m "feat: bootstrap minimal C64 program"
```

---

## Task 2: Memory Map and Zero Page Setup

**Files:**
- Create: `src/zeropage.asm`
- Modify: `src/main.asm`

**Step 1: Define zero page variables**

```asm
; src/zeropage.asm
; Zero page variable definitions
; $02-$7F available for user programs

; Temporary registers
zp_temp1        = $02
zp_temp2        = $03
zp_temp3        = $04
zp_temp4        = $05

; Pointers (16-bit)
zp_ptr1         = $06           ; $06-$07
zp_ptr2         = $08           ; $08-$09

; Serial state
zp_rx_head      = $0a
zp_rx_tail      = $0b
zp_tx_head      = $0c
zp_tx_tail      = $0d

; Game state
zp_player_id    = $10           ; $10-$11 (16-bit)
zp_game_id      = $12           ; $12-$13 (16-bit)
zp_sequence     = $14           ; $14-$15 (16-bit)
zp_my_index     = $16           ; Our player index (0-7)
zp_current_turn = $17           ; Current player's turn
zp_hand_count   = $18           ; Cards in our hand
zp_cursor_pos   = $19           ; Cursor position in hand
zp_selected     = $1a           ; Bitmask of selected cards (up to 8)

; Screen state
zp_screen_ptr   = $20           ; $20-$21 screen pointer
zp_color_ptr    = $22           ; $22-$23 color RAM pointer

; Connection state
zp_conn_state   = $30           ; 0=disconnected, 1=connecting, 2=connected, 3=in_game
```

**Step 2: Include in main.asm**

Add at top of main.asm after header:
```asm
        !source "src/zeropage.asm"
```

**Step 3: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 4: Commit**

```bash
git add src/zeropage.asm src/main.asm
git commit -m "feat: add zero page variable definitions"
```

---

## Task 3: Serial Buffer Setup

**Files:**
- Create: `src/buffers.asm`
- Modify: `src/main.asm`

**Step 1: Define buffer locations**

```asm
; src/buffers.asm
; Fixed memory buffers for serial and game data

; Serial buffers at $0200
SERIAL_RX_BUF   = $0200         ; 64 bytes receive buffer
SERIAL_TX_BUF   = $0240         ; 64 bytes transmit buffer
AT_CMD_BUF      = $0280         ; 64 bytes AT command buffer
AT_RESP_BUF     = $02c0         ; 64 bytes AT response buffer

; Game state at $0300
PLAYER_NAMES    = $0300         ; 8 players x 16 chars = 128 bytes
PLAYER_COUNTS   = $0380         ; 8 bytes (card count per player)
MY_HAND         = $0388         ; 32 bytes max (32 cards)
DISCARD_TOP     = $03a8         ; 1 byte (current top card)
NOMINATED_SUIT  = $03a9         ; 1 byte (0-3 or $FF)
PENDING_DRAWS   = $03aa         ; 1 byte
DECK_COUNT      = $03ab         ; 1 byte
DIRECTION       = $03ac         ; 0=clockwise, 1=counter

; Buffer sizes
RX_BUF_SIZE     = 64
TX_BUF_SIZE     = 64
AT_BUF_SIZE     = 64
MAX_HAND_SIZE   = 32
MAX_PLAYERS     = 8
NAME_LENGTH     = 16
```

**Step 2: Add initialization routine**

```asm
; Initialize all buffers to zero
init_buffers:
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

        ; Clear game state
        ldx #0
.clear_game:
        sta $0300,x
        inx
        bne .clear_game

        ; Initialize buffer pointers
        sta zp_rx_head
        sta zp_rx_tail
        sta zp_tx_head
        sta zp_tx_tail
        rts
```

**Step 3: Call from main**

Add to main.asm start routine:
```asm
        jsr init_buffers
```

**Step 4: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 5: Commit**

```bash
git add src/buffers.asm src/main.asm
git commit -m "feat: add serial and game state buffers"
```

---

## Task 4: Screen Module - Basic Text Output

**Files:**
- Create: `src/screen.asm`
- Modify: `src/main.asm`

**Step 1: Create screen utilities**

```asm
; src/screen.asm
; PETSCII screen rendering utilities

SCREEN_RAM      = $0400
COLOR_RAM       = $d800
SCREEN_WIDTH    = 40
SCREEN_HEIGHT   = 25

; Colors
COL_BLACK       = 0
COL_WHITE       = 1
COL_RED         = 2
COL_CYAN        = 3
COL_PURPLE      = 4
COL_GREEN       = 5
COL_BLUE        = 6
COL_YELLOW      = 7
COL_LIGHT_BLUE  = 14

; Clear screen and set colors
screen_init:
        ; Set border and background to blue
        lda #COL_BLUE
        sta $d020               ; Border
        sta $d021               ; Background

        ; Clear screen
        lda #$93
        jsr $ffd2

        ; Set text color to white
        lda #COL_WHITE
        sta $0286               ; Current color
        rts

; Print null-terminated string
; Input: zp_ptr1 points to string
screen_print:
        ldy #0
.loop:
        lda (zp_ptr1),y
        beq .done
        jsr $ffd2               ; CHROUT
        iny
        bne .loop
.done:
        rts

; Print string at X,Y position
; Input: X=column, Y=row, zp_ptr1=string
screen_print_at:
        ; Calculate screen position
        clc
        jsr $fff0               ; PLOT (set cursor)
        jsr screen_print
        rts

; Draw horizontal line
; Input: X=start column, Y=row, A=length
screen_hline:
        stx zp_temp1            ; Save start X
        sta zp_temp2            ; Save length
        clc
        jsr $fff0               ; Set cursor position

        ldx zp_temp2
.loop:
        lda #$40                ; Horizontal line char
        jsr $ffd2
        dex
        bne .loop
        rts

; Set cursor position
; Input: X=column, Y=row
screen_goto:
        clc
        jsr $fff0               ; PLOT
        rts
```

**Step 2: Update main to use screen module**

```asm
        !source "src/screen.asm"

start:
        jsr init_buffers
        jsr screen_init
        jsr draw_title
        ; ... rest of code
```

**Step 3: Build and test**

Run: `make run`
Expected: Blue screen with white text

**Step 4: Commit**

```bash
git add src/screen.asm src/main.asm
git commit -m "feat: add screen module with basic text output"
```

---

## Task 5: Screen Layout - Title and Frame

**Files:**
- Modify: `src/screen.asm`
- Modify: `src/main.asm`

**Step 1: Add title drawing routine**

```asm
; Draw the game title bar
draw_title:
        ; Position at top center
        ldx #12
        ldy #0
        clc
        jsr $fff0

        ; Print title
        ldx #0
.loop:
        lda title_text,x
        beq .done
        jsr $ffd2
        inx
        bne .loop
.done:
        rts

title_text:
        !text "RACHEL V1.0"
        !byte 0

; Draw main game frame
draw_frame:
        ; Top border (row 1)
        ldx #0
        ldy #1
        lda #40
        jsr screen_hline

        ; Player section border (row 4)
        ldx #0
        ldy #4
        lda #40
        jsr screen_hline

        ; Discard section border (row 11)
        ldx #0
        ldy #11
        lda #40
        jsr screen_hline

        ; Hand section border (row 19)
        ldx #0
        ldy #19
        lda #40
        jsr screen_hline

        ; Status section border (row 22)
        ldx #0
        ldy #22
        lda #40
        jsr screen_hline
        rts
```

**Step 2: Call from main**

```asm
start:
        jsr init_buffers
        jsr screen_init
        jsr draw_title
        jsr draw_frame
```

**Step 3: Build and test**

Run: `make run`
Expected: Title centered at top, horizontal divider lines visible

**Step 4: Commit**

```bash
git add src/screen.asm src/main.asm
git commit -m "feat: add title bar and screen frame layout"
```

---

## Task 6: Input Module - Keyboard Scanning

**Files:**
- Create: `src/input.asm`
- Modify: `src/main.asm`

**Step 1: Create keyboard input module**

```asm
; src/input.asm
; Keyboard input handling

; Key codes (PETSCII)
KEY_LEFT        = $9d           ; Cursor left
KEY_RIGHT       = $1d           ; Cursor right
KEY_UP          = $91           ; Cursor up
KEY_DOWN        = $11           ; Cursor down
KEY_RETURN      = $0d           ; Return/Enter
KEY_SPACE       = $20           ; Space
KEY_P           = $50           ; P (play)
KEY_D           = $44           ; D (draw)
KEY_Q           = $51           ; Q (quit)

; Last key pressed (0 if none)
last_key:       !byte 0

; Check for keypress (non-blocking)
; Returns: A=key code, or 0 if no key
input_scan:
        jsr $ffe4               ; GETIN
        sta last_key
        rts

; Wait for any keypress (blocking)
; Returns: A=key code
input_wait:
.loop:
        jsr $ffe4
        beq .loop
        sta last_key
        rts

; Wait for specific key from list
; Input: zp_ptr1 = pointer to null-terminated key list
; Returns: A=key pressed (from list)
input_wait_for:
        jsr input_wait
        ldy #0
.check:
        lda (zp_ptr1),y
        beq input_wait_for      ; Not in list, wait again
        cmp last_key
        beq .found
        iny
        bne .check
.found:
        lda last_key
        rts
```

**Step 2: Include in main.asm**

```asm
        !source "src/input.asm"
```

**Step 3: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 4: Commit**

```bash
git add src/input.asm src/main.asm
git commit -m "feat: add keyboard input module"
```

---

## Task 7: Serial Module - User Port Setup

**Files:**
- Create: `src/serial.asm`
- Modify: `src/main.asm`

**Step 1: Create serial I/O module**

```asm
; src/serial.asm
; User Port serial communication at 2400 baud

; CIA2 registers for User Port
CIA2_PRA        = $dd00         ; Port A data
CIA2_PRB        = $dd01         ; Port B data
CIA2_DDRA       = $dd02         ; Data direction A
CIA2_DDRB       = $dd03         ; Data direction B
CIA2_TA_LO      = $dd04         ; Timer A low byte
CIA2_TA_HI      = $dd05         ; Timer A high byte
CIA2_TB_LO      = $dd06         ; Timer B low byte
CIA2_TB_HI      = $dd07         ; Timer B high byte
CIA2_ICR        = $dd0d         ; Interrupt control
CIA2_CRA        = $dd0e         ; Control register A
CIA2_CRB        = $dd0f         ; Control register B

; User Port bits (accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent accent)
; PA2 = TXD (active low, directly outputs serial data), directly from CIA2
; FLAG (directly as receive data), directly from CIA2
; directly from CIA2
; directly from CIA2
; The C64 User Port directly exposes only the directly raw interface
; directly
; For bit-banging serial at 2400 baud on a 1MHz 6502:
; Bit time = 1000000 / 2400 = 416.67 cycles
BIT_DELAY       = 410           ; Cycles per bit (adjusted for overhead)

; Initialize User Port for serial
serial_init:
        ; Disable interrupts during setup
        sei

        ; Set PA2 as output (TXD)
        lda CIA2_DDRA
        ora #%00000100          ; PA2 output
        sta CIA2_DDRA

        ; Set TXD high (idle)
        lda CIA2_PRA
        ora #%00000100          ; PA2 high
        sta CIA2_PRA

        cli
        rts

; Send one byte (blocking, bit-banged)
; Input: A = byte to send
serial_send_byte:
        sei
        sta zp_temp1            ; Save byte
        ldx #8                  ; 8 data bits

        ; Start bit (low)
        lda CIA2_PRA
        and #%11111011          ; PA2 low
        sta CIA2_PRA
        jsr bit_delay

        ; Data bits (LSB first)
.send_bit:
        lsr zp_temp1            ; Shift LSB into carry
        lda CIA2_PRA
        bcc .send_low
        ora #%00000100          ; High bit
        bne .send_store
.send_low:
        and #%11111011          ; Low bit
.send_store:
        sta CIA2_PRA
        jsr bit_delay
        dex
        bne .send_bit

        ; Stop bit (high)
        lda CIA2_PRA
        ora #%00000100          ; PA2 high
        sta CIA2_PRA
        jsr bit_delay

        cli
        rts

; Receive one byte (blocking, bit-banged)
; Returns: A = received byte
serial_recv_byte:
        sei
        lda #0
        sta zp_temp1            ; Clear result

        ; Wait for start bit (high to low transition on FLAG)
.wait_start:
        lda CIA2_PRB
        and #%00010000          ; FLAG bit
        bne .wait_start         ; Wait while high

        ; Half bit delay to sample in middle
        jsr half_bit_delay

        ; Read 8 data bits
        ldx #8
.recv_bit:
        jsr bit_delay
        lda CIA2_PRB
        and #%00010000          ; FLAG bit
        clc
        beq .recv_low
        sec                     ; Set carry if high
.recv_low:
        ror zp_temp1            ; Rotate carry into MSB
        dex
        bne .recv_bit

        ; Wait for stop bit
        jsr bit_delay

        cli
        lda zp_temp1
        rts

; Bit timing delays
bit_delay:
        ; ~410 cycles for 2400 baud
        ldy #82
.loop:
        dey
        bne .loop
        rts

half_bit_delay:
        ldy #41
.loop:
        dey
        bne .loop
        rts

; Check if data available (non-blocking)
; Returns: Z=1 if no data, Z=0 if data ready
serial_available:
        lda CIA2_PRB
        and #%00010000          ; FLAG bit
        rts
```

**Step 2: Include in main.asm**

```asm
        !source "src/serial.asm"
```

**Step 3: Add serial init to startup**

```asm
start:
        jsr init_buffers
        jsr screen_init
        jsr serial_init
        ; ...
```

**Step 4: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 5: Commit**

```bash
git add src/serial.asm src/main.asm
git commit -m "feat: add User Port serial module (2400 baud)"
```

---

## Task 8: Modem Module - AT Commands

**Files:**
- Create: `src/modem.asm`
- Modify: `src/main.asm`

**Step 1: Create AT command handler**

```asm
; src/modem.asm
; Zimodem AT command handling

; Send AT command and wait for response
; Input: zp_ptr1 = pointer to command string (without AT prefix)
; Returns: A = 0 if OK, 1 if ERROR, 2 if timeout
modem_send_cmd:
        ; Send "AT"
        lda #'A'
        jsr serial_send_byte
        lda #'T'
        jsr serial_send_byte

        ; Send command string
        ldy #0
.send_loop:
        lda (zp_ptr1),y
        beq .send_cr
        jsr serial_send_byte
        iny
        bne .send_loop

.send_cr:
        ; Send CR
        lda #$0d
        jsr serial_send_byte

        ; Wait for response
        jmp modem_wait_response

; Wait for OK or ERROR response
; Returns: A = 0 if OK, 1 if ERROR, 2 if timeout
modem_wait_response:
        ; Simple implementation: look for 'O' (OK) or 'E' (ERROR)
        ; Timeout after ~5 seconds (adjust counter as needed)
        lda #0
        sta zp_temp3            ; Timeout counter low
        sta zp_temp4            ; Timeout counter high

.wait_loop:
        ; Check for timeout
        inc zp_temp3
        bne .no_overflow
        inc zp_temp4
        lda zp_temp4
        cmp #$20                ; Timeout threshold
        bcs .timeout
.no_overflow:

        ; Check for data
        jsr serial_available
        bne .wait_loop          ; No data, keep waiting

        ; Read character
        jsr serial_recv_byte
        cmp #'O'                ; Start of "OK"
        beq .got_ok
        cmp #'E'                ; Start of "ERROR"
        beq .got_error
        bne .wait_loop

.got_ok:
        lda #0
        rts

.got_error:
        lda #1
        rts

.timeout:
        lda #2
        rts

; Reset modem (ATZ)
modem_reset:
        lda #<cmd_z
        sta zp_ptr1
        lda #>cmd_z
        sta zp_ptr1+1
        jsr modem_send_cmd
        rts

cmd_z:
        !text "Z"
        !byte 0

; Dial TCP connection
; Input: zp_ptr1 = pointer to "ip:port" string
modem_dial:
        ; Save IP string pointer
        lda zp_ptr1
        sta zp_temp1
        lda zp_ptr1+1
        sta zp_temp2

        ; Point to ATDT prefix
        lda #<cmd_dt
        sta zp_ptr1
        lda #>cmd_dt
        sta zp_ptr1+1

        ; Send "AT"
        lda #'A'
        jsr serial_send_byte
        lda #'T'
        jsr serial_send_byte

        ; Send "DT"
        ldy #0
.send_dt:
        lda (zp_ptr1),y
        beq .send_ip
        jsr serial_send_byte
        iny
        bne .send_dt

.send_ip:
        ; Restore IP pointer
        lda zp_temp1
        sta zp_ptr1
        lda zp_temp2
        sta zp_ptr1+1

        ; Send IP:port
        ldy #0
.send_ip_loop:
        lda (zp_ptr1),y
        beq .send_done
        jsr serial_send_byte
        iny
        bne .send_ip_loop

.send_done:
        lda #$0d
        jsr serial_send_byte

        ; Wait for CONNECT or NO CARRIER
        jmp modem_wait_connect

cmd_dt:
        !text "DT"
        !byte 0

; Wait for CONNECT response
; Returns: A = 0 if connected, 1 if failed
modem_wait_connect:
        ; Look for 'C' (CONNECT) or 'N' (NO CARRIER)
        lda #0
        sta zp_temp3
        sta zp_temp4

.wait_loop:
        inc zp_temp3
        bne .no_overflow
        inc zp_temp4
        lda zp_temp4
        cmp #$40                ; Longer timeout for connect
        bcs .timeout
.no_overflow:

        jsr serial_available
        bne .wait_loop

        jsr serial_recv_byte
        cmp #'C'
        beq .connected
        cmp #'N'
        beq .failed
        bne .wait_loop

.connected:
        lda #0
        rts

.failed:
.timeout:
        lda #1
        rts
```

**Step 2: Include in main.asm**

```asm
        !source "src/modem.asm"
```

**Step 3: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 4: Commit**

```bash
git add src/modem.asm src/main.asm
git commit -m "feat: add modem module for Zimodem AT commands"
```

---

## Task 9: RUBP Module - Message Building

**Files:**
- Create: `src/rubp.asm`
- Modify: `src/main.asm`

**Step 1: Create RUBP message builder**

```asm
; src/rubp.asm
; RUBP protocol message handling

; Message types
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

; Platform ID for C64
PLATFORM_C64    = $0003

; Header offsets
HDR_MAGIC       = 0             ; 4 bytes "RACH"
HDR_VERSION     = 4             ; 1 byte
HDR_TYPE        = 5             ; 1 byte
HDR_SEQUENCE    = 6             ; 2 bytes (big-endian)
HDR_PLAYER_ID   = 8             ; 2 bytes (big-endian)
HDR_GAME_ID     = 10            ; 2 bytes (big-endian)
HDR_TIMESTAMP   = 12            ; 4 bytes (big-endian)

; Payload starts at offset 16
PAYLOAD_START   = 16
MSG_SIZE        = 64

; Build message header in TX buffer
; Input: A = message type
rubp_build_header:
        sta zp_temp1            ; Save message type

        ; Clear TX buffer
        ldx #0
        lda #0
.clear:
        sta SERIAL_TX_BUF,x
        inx
        cpx #MSG_SIZE
        bne .clear

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

        ; Sequence number (big-endian)
        lda zp_sequence+1       ; High byte first
        sta SERIAL_TX_BUF+HDR_SEQUENCE
        lda zp_sequence         ; Low byte second
        sta SERIAL_TX_BUF+HDR_SEQUENCE+1

        ; Increment sequence
        inc zp_sequence
        bne .no_carry
        inc zp_sequence+1
.no_carry:

        ; Player ID (big-endian)
        lda zp_player_id+1
        sta SERIAL_TX_BUF+HDR_PLAYER_ID
        lda zp_player_id
        sta SERIAL_TX_BUF+HDR_PLAYER_ID+1

        ; Game ID (big-endian)
        lda zp_game_id+1
        sta SERIAL_TX_BUF+HDR_GAME_ID
        lda zp_game_id
        sta SERIAL_TX_BUF+HDR_GAME_ID+1

        ; Timestamp = 0 (we don't track time)
        ; Already cleared
        rts

; Send TX buffer (64 bytes)
rubp_send:
        ldx #0
.loop:
        lda SERIAL_TX_BUF,x
        jsr serial_send_byte
        inx
        cpx #MSG_SIZE
        bne .loop
        rts

; Receive message into RX buffer (64 bytes, blocking)
rubp_receive:
        ldx #0
.loop:
        jsr serial_recv_byte
        sta SERIAL_RX_BUF,x
        inx
        cpx #MSG_SIZE
        bne .loop
        rts

; Validate RX buffer has valid RUBP header
; Returns: Z=1 if valid, Z=0 if invalid
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

        ; Valid - set Z flag
        lda #0
        rts

.invalid:
        lda #1
        rts

; Get message type from RX buffer
; Returns: A = message type
rubp_get_type:
        lda SERIAL_RX_BUF+HDR_TYPE
        rts
```

**Step 2: Include in main.asm**

```asm
        !source "src/rubp.asm"
```

**Step 3: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 4: Commit**

```bash
git add src/rubp.asm src/main.asm
git commit -m "feat: add RUBP message building and validation"
```

---

## Task 10: RUBP Module - HELLO Message

**Files:**
- Modify: `src/rubp.asm`
- Add: Player name input to `src/main.asm`

**Step 1: Add HELLO message builder**

Add to `src/rubp.asm`:

```asm
; Build and send HELLO message
; Input: zp_ptr1 = pointer to player name (null-terminated)
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

        ; Platform ID at offset 16 (big-endian)
        lda #$00                ; High byte
        sta SERIAL_TX_BUF+PAYLOAD_START+16
        lda #$03                ; Low byte (C64 = 0x0003)
        sta SERIAL_TX_BUF+PAYLOAD_START+17

        ; Send message
        jmp rubp_send
```

**Step 2: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add src/rubp.asm
git commit -m "feat: add RUBP HELLO message builder"
```

---

## Task 11: RUBP Module - Parse WELCOME

**Files:**
- Modify: `src/rubp.asm`

**Step 1: Add WELCOME parser**

Add to `src/rubp.asm`:

```asm
; Parse WELCOME message from RX buffer
; Extracts PlayerID, GameID, stores in zero page
rubp_parse_welcome:
        ; Player ID (big-endian at payload+0)
        lda SERIAL_RX_BUF+PAYLOAD_START+1  ; Low byte
        sta zp_player_id
        lda SERIAL_RX_BUF+PAYLOAD_START    ; High byte
        sta zp_player_id+1

        ; Game ID (big-endian at payload+2)
        lda SERIAL_RX_BUF+PAYLOAD_START+3  ; Low byte
        sta zp_game_id
        lda SERIAL_RX_BUF+PAYLOAD_START+2  ; High byte
        sta zp_game_id+1

        ; Player count at payload+4
        lda SERIAL_RX_BUF+PAYLOAD_START+4
        sta zp_temp1                        ; Store for caller

        ; Game state at payload+5
        ; 0=WAITING, 1=PLAYING, 2=FINISHED
        lda SERIAL_RX_BUF+PAYLOAD_START+5
        sta zp_conn_state                   ; Update connection state
        rts
```

**Step 2: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add src/rubp.asm
git commit -m "feat: add RUBP WELCOME message parser"
```

---

## Task 12: RUBP Module - Parse GAME_STATE

**Files:**
- Modify: `src/rubp.asm`

**Step 1: Add GAME_STATE parser**

Add to `src/rubp.asm`:

```asm
; Parse GAME_STATE message from RX buffer
; Updates all game state variables
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

        ; Pending skips (payload+5) - not used in display

        ; Deck count (payload+6)
        lda SERIAL_RX_BUF+PAYLOAD_START+6
        sta DECK_COUNT

        ; Player card counts (payload+7 to +14, 8 bytes)
        ldx #0
.copy_counts:
        lda SERIAL_RX_BUF+PAYLOAD_START+7,x
        sta PLAYER_COUNTS,x
        inx
        cpx #MAX_PLAYERS
        bne .copy_counts

        ; Is game over (payload+15)
        ; Winner index (payload+16)
        ; Handle in main loop
        rts
```

**Step 2: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add src/rubp.asm
git commit -m "feat: add RUBP GAME_STATE message parser"
```

---

## Task 13: RUBP Module - Parse CARD_DRAWN and GAME_START

**Files:**
- Modify: `src/rubp.asm`

**Step 1: Add card message parsers**

Add to `src/rubp.asm`:

```asm
; Parse GAME_START or CARD_DRAWN message
; Both have same format: count + cards
; Adds cards to MY_HAND (GAME_START replaces, CARD_DRAWN appends)
; Input: A = 0 for replace (GAME_START), A = 1 for append (CARD_DRAWN)
rubp_parse_cards:
        sta zp_temp1            ; Save mode

        ; Card count at payload+0
        lda SERIAL_RX_BUF+PAYLOAD_START
        sta zp_temp2            ; Number of cards

        ; Get starting index in hand
        lda zp_temp1
        bne .append
        ; Replace mode - start at 0
        lda #0
        sta zp_hand_count
        beq .start_copy

.append:
        ; Append mode - start at current count
        ; (hand count already set)

.start_copy:
        ldx zp_hand_count       ; Destination index
        ldy #0                  ; Source index

.copy_loop:
        cpy zp_temp2
        beq .done
        lda SERIAL_RX_BUF+PAYLOAD_START+1,y  ; Cards start at payload+1
        sta MY_HAND,x
        inx
        iny
        cpx #MAX_HAND_SIZE
        bne .copy_loop

.done:
        stx zp_hand_count       ; Update hand count
        rts

; Convenience wrappers
rubp_parse_game_start:
        lda #0                  ; Replace mode
        jmp rubp_parse_cards

rubp_parse_card_drawn:
        lda #1                  ; Append mode
        jmp rubp_parse_cards
```

**Step 2: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add src/rubp.asm
git commit -m "feat: add GAME_START and CARD_DRAWN parsers"
```

---

## Task 14: RUBP Module - Build PLAY_CARD and DRAW_CARD

**Files:**
- Modify: `src/rubp.asm`

**Step 1: Add action message builders**

Add to `src/rubp.asm`:

```asm
; Build and send PLAY_CARD message
; Input: zp_temp1 = card count, zp_temp2 = nominated suit ($FF if none)
;        Selected cards marked in zp_selected bitmask
rubp_send_play_card:
        ; Build header
        lda #MSG_PLAY_CARD
        jsr rubp_build_header

        ; Card count at payload+0
        lda zp_temp1
        sta SERIAL_TX_BUF+PAYLOAD_START

        ; Copy selected cards to payload+1
        ldx #0                  ; Source index in hand
        ldy #0                  ; Dest index in payload
        lda #1                  ; Bit mask

.check_card:
        cpx zp_hand_count
        beq .cards_done
        pha                     ; Save mask
        and zp_selected
        beq .not_selected

        ; Card is selected - copy it
        lda MY_HAND,x
        sta SERIAL_TX_BUF+PAYLOAD_START+1,y
        iny

.not_selected:
        pla                     ; Restore mask
        asl                     ; Next bit
        bne .next_card
        lda #1                  ; Wrap around (shouldn't happen with 8 cards max selected)
.next_card:
        inx
        bne .check_card

.cards_done:
        ; Nominated suit at payload+33
        lda zp_temp2
        sta SERIAL_TX_BUF+PAYLOAD_START+33

        ; Send
        jmp rubp_send

; Build and send DRAW_CARD message
; Input: A = reason (0=can't play, 1=attack penalty)
rubp_send_draw_card:
        sta zp_temp1            ; Save reason

        ; Build header
        lda #MSG_DRAW_CARD
        jsr rubp_build_header

        ; Reason at payload+0
        lda zp_temp1
        sta SERIAL_TX_BUF+PAYLOAD_START

        ; Count at payload+1 (always 1 for manual draw)
        lda #1
        sta SERIAL_TX_BUF+PAYLOAD_START+1

        ; Send
        jmp rubp_send
```

**Step 2: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add src/rubp.asm
git commit -m "feat: add PLAY_CARD and DRAW_CARD message builders"
```

---

## Task 15: Game Module - Card Display

**Files:**
- Create: `src/game.asm`
- Modify: `src/main.asm`

**Step 1: Create game display module**

```asm
; src/game.asm
; Game state management and card display

; Suit names (PETSCII)
suit_names:
        !text "H"               ; Hearts (could use PETSCII heart)
        !text "D"               ; Diamonds
        !text "C"               ; Clubs
        !text "S"               ; Spades

; Rank names
rank_names:
        !text "  23456789TJQKA"  ; Index 0-1 unused, 2-14 valid

; Decode card byte to suit and rank
; Input: A = encoded card
; Output: X = suit (0-3), Y = rank (2-14)
decode_card:
        sta zp_temp1
        and #$3f                ; Mask rank bits
        tay                     ; Y = rank

        lda zp_temp1
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr                     ; Shift suit to bits 0-1
        tax                     ; X = suit
        rts

; Print card at current cursor position
; Input: A = encoded card
print_card:
        jsr decode_card         ; X=suit, Y=rank

        ; Set color based on suit
        cpx #2                  ; Clubs or Spades?
        bcs .black_suit
        lda #COL_RED
        bne .set_color
.black_suit:
        lda #COL_WHITE
.set_color:
        sta $0286               ; Current text color

        ; Print rank
        lda rank_names,y
        jsr $ffd2

        ; Print suit
        lda suit_names,x
        jsr $ffd2

        ; Reset color
        lda #COL_WHITE
        sta $0286
        rts

; Draw player's hand
; Displays cards in grid format with selection markers
draw_hand:
        ; Position at hand area (row 14)
        ldx #2
        ldy #14
        jsr screen_goto

        ldx #0                  ; Card index
        lda #1                  ; Selection bit mask
        sta zp_temp3

.card_loop:
        cpx zp_hand_count
        beq .done

        ; Check if this card is selected
        lda zp_temp3
        and zp_selected
        beq .not_selected

        ; Show selection bracket
        lda #'>'
        jsr $ffd2
        bne .print_it

.not_selected:
        lda #' '
        jsr $ffd2

.print_it:
        ; Print the card
        lda MY_HAND,x
        jsr print_card

        ; Closing bracket if selected
        lda zp_temp3
        and zp_selected
        beq .no_close
        lda #'<'
        jsr $ffd2
        lda #' '
        jsr $ffd2
        bne .next
.no_close:
        lda #' '
        jsr $ffd2
        jsr $ffd2

.next:
        ; Move to next card
        inx

        ; Check for row wrap (6 cards per row)
        txa
        and #$05                ; X mod 6 (approximately)
        ; TODO: proper modulo for row wrapping

        ; Shift selection mask
        asl zp_temp3
        bne .card_loop
        lda #1
        sta zp_temp3
        bne .card_loop

.done:
        rts

; Draw discard pile
draw_discard:
        ; Position at center (row 7)
        ldx #17
        ldy #7
        jsr screen_goto

        ; Draw card box
        lda #$70                ; Top-left corner
        jsr $ffd2
        lda #$40                ; Horizontal line
        jsr $ffd2
        jsr $ffd2
        jsr $ffd2
        jsr $ffd2
        lda #$6e                ; Top-right corner
        jsr $ffd2

        ; Middle row with card
        ldx #17
        ldy #8
        jsr screen_goto
        lda #$5d                ; Vertical line
        jsr $ffd2
        lda #' '
        jsr $ffd2

        lda DISCARD_TOP
        jsr print_card

        lda #' '
        jsr $ffd2
        lda #$5d
        jsr $ffd2

        ; Bottom row
        ldx #17
        ldy #9
        jsr screen_goto
        lda #$6d                ; Bottom-left
        jsr $ffd2
        lda #$40
        jsr $ffd2
        jsr $ffd2
        jsr $ffd2
        jsr $ffd2
        lda #$7d                ; Bottom-right
        jsr $ffd2

        rts
```

**Step 2: Include in main.asm**

```asm
        !source "src/game.asm"
```

**Step 3: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 4: Commit**

```bash
git add src/game.asm src/main.asm
git commit -m "feat: add game display module with card rendering"
```

---

## Task 16: Connection Flow - IP Entry Screen

**Files:**
- Modify: `src/main.asm`
- Modify: `src/screen.asm`

**Step 1: Add IP address input**

Add to `src/screen.asm`:

```asm
; IP address input buffer
ip_buffer:      !fill 24, 0     ; "xxx.xxx.xxx.xxx:xxxxx" + null

; Get IP address from user
; Returns: ip_buffer filled with address:port
screen_get_ip:
        ; Print prompt
        ldx #5
        ldy #12
        jsr screen_goto

        lda #<ip_prompt
        sta zp_ptr1
        lda #>ip_prompt
        sta zp_ptr1+1
        jsr screen_print

        ; Position for input
        ldx #5
        ldy #14
        jsr screen_goto

        ; Read input character by character
        ldx #0                  ; Buffer index
.input_loop:
        jsr input_wait

        cmp #KEY_RETURN
        beq .done

        cmp #$14                ; Delete key
        beq .delete

        ; Only accept digits, dots, colons
        cmp #'0'
        bcc .input_loop
        cmp #':'
        beq .store
        cmp #'9'+1
        bcc .store
        cmp #'.'
        bne .input_loop

.store:
        cpx #23                 ; Max length
        bcs .input_loop

        sta ip_buffer,x
        jsr $ffd2               ; Echo character
        inx
        bne .input_loop

.delete:
        cpx #0
        beq .input_loop
        dex
        lda #0
        sta ip_buffer,x
        lda #$9d                ; Cursor left
        jsr $ffd2
        lda #' '
        jsr $ffd2
        lda #$9d
        jsr $ffd2
        bne .input_loop

.done:
        lda #0
        sta ip_buffer,x         ; Null terminate
        rts

ip_prompt:
        !text "ENTER HOST IP:PORT"
        !byte 0
```

**Step 2: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add src/screen.asm
git commit -m "feat: add IP address input screen"
```

---

## Task 17: Connection Flow - Connect Sequence

**Files:**
- Modify: `src/main.asm`

**Step 1: Implement connection flow in main**

Update `src/main.asm`:

```asm
; Main entry point
start:
        jsr init_buffers
        jsr screen_init
        jsr serial_init
        jsr draw_title

        ; Show connecting message
        ldx #5
        ldy #10
        jsr screen_goto
        lda #<msg_init_modem
        sta zp_ptr1
        lda #>msg_init_modem
        sta zp_ptr1+1
        jsr screen_print

        ; Reset modem
        jsr modem_reset
        cmp #0
        bne connection_failed

        ; Get IP from user
        jsr screen_get_ip

        ; Show connecting status
        ldx #5
        ldy #16
        jsr screen_goto
        lda #<msg_connecting
        sta zp_ptr1
        lda #>msg_connecting
        sta zp_ptr1+1
        jsr screen_print

        ; Dial
        lda #<ip_buffer
        sta zp_ptr1
        lda #>ip_buffer
        sta zp_ptr1+1
        jsr modem_dial
        cmp #0
        bne connection_failed

        ; Connected! Send HELLO
        jsr send_hello
        cmp #0
        bne connection_failed

        ; Wait for WELCOME
        jsr wait_welcome
        cmp #0
        bne connection_failed

        ; Enter main game loop
        jmp game_loop

connection_failed:
        ldx #5
        ldy #20
        jsr screen_goto
        lda #<msg_failed
        sta zp_ptr1
        lda #>msg_failed
        sta zp_ptr1+1
        jsr screen_print

        ; Wait for key and restart
        jsr input_wait
        jmp start

; Send HELLO with player name
send_hello:
        lda #<player_name
        sta zp_ptr1
        lda #>player_name
        sta zp_ptr1+1
        jsr rubp_send_hello
        lda #0
        rts

; Wait for WELCOME response
wait_welcome:
        jsr rubp_receive
        jsr rubp_validate
        bne .invalid

        jsr rubp_get_type
        cmp #MSG_WELCOME
        bne .invalid

        jsr rubp_parse_welcome
        lda #0
        rts

.invalid:
        lda #1
        rts

msg_init_modem:
        !text "INITIALIZING MODEM..."
        !byte 0

msg_connecting:
        !text "CONNECTING..."
        !byte 0

msg_failed:
        !text "CONNECTION FAILED. PRESS ANY KEY."
        !byte 0

player_name:
        !text "C64 PLAYER"
        !byte 0
```

**Step 2: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add src/main.asm
git commit -m "feat: implement connection flow with modem dial"
```

---

## Task 18: Main Game Loop

**Files:**
- Modify: `src/main.asm`

**Step 1: Implement game loop**

Add to `src/main.asm`:

```asm
; Main game loop
game_loop:
        ; Draw initial game screen
        jsr screen_init
        jsr draw_title
        jsr draw_frame

.loop:
        ; Check for incoming message
        jsr serial_available
        bne .check_input        ; No data

        ; Receive and process message
        jsr rubp_receive
        jsr rubp_validate
        bne .loop               ; Invalid, skip

        jsr rubp_get_type
        cmp #MSG_GAME_STATE
        beq .handle_game_state
        cmp #MSG_CARD_DRAWN
        beq .handle_card_drawn
        cmp #MSG_GAME_START
        beq .handle_game_start
        cmp #MSG_PLAYER_WON
        beq .handle_game_over
        cmp #MSG_ERROR
        beq .handle_error
        bne .loop               ; Unknown type

.handle_game_state:
        jsr rubp_parse_game_state
        jsr redraw_game
        jmp .loop

.handle_card_drawn:
        jsr rubp_parse_card_drawn
        jsr draw_hand
        jmp .loop

.handle_game_start:
        jsr rubp_parse_game_start
        lda #3                  ; In game state
        sta zp_conn_state
        jsr redraw_game
        jmp .loop

.handle_game_over:
        jsr show_winner
        jsr input_wait
        jmp start               ; Restart

.handle_error:
        jsr show_error
        jmp .loop

.check_input:
        ; Only process input on our turn
        lda zp_current_turn
        cmp zp_my_index
        bne .loop               ; Not our turn

        ; Check for keypress
        jsr input_scan
        beq .loop               ; No key

        cmp #KEY_LEFT
        beq .move_left
        cmp #KEY_RIGHT
        beq .move_right
        cmp #KEY_SPACE
        beq .toggle_select
        cmp #KEY_P
        beq .play_cards
        cmp #KEY_D
        beq .draw_card
        jmp .loop

.move_left:
        lda zp_cursor_pos
        beq .loop               ; Already at start
        dec zp_cursor_pos
        jsr draw_hand
        jmp .loop

.move_right:
        lda zp_cursor_pos
        cmp zp_hand_count
        bcs .loop               ; Already at end
        inc zp_cursor_pos
        jsr draw_hand
        jmp .loop

.toggle_select:
        ; Toggle selection bit for current card
        ldx zp_cursor_pos
        lda #1
.shift_mask:
        dex
        bmi .apply_toggle
        asl
        bne .shift_mask
.apply_toggle:
        eor zp_selected
        sta zp_selected
        jsr draw_hand
        jmp .loop

.play_cards:
        ; Count selected cards
        lda zp_selected
        beq .loop               ; Nothing selected

        jsr count_selected
        sta zp_temp1            ; Card count

        ; Check for ace nomination
        lda #$ff                ; No nomination
        sta zp_temp2
        ; TODO: prompt for suit if playing ace

        jsr rubp_send_play_card

        ; Clear selection
        lda #0
        sta zp_selected
        jmp .loop

.draw_card:
        lda #0                  ; Reason: can't play
        jsr rubp_send_draw_card
        jmp .loop

; Count bits set in zp_selected
; Returns: A = count
count_selected:
        lda zp_selected
        ldx #0
.count_loop:
        lsr
        bcc .no_inc
        inx
.no_inc:
        bne .count_loop
        txa
        rts

; Redraw entire game state
redraw_game:
        jsr draw_players
        jsr draw_discard
        jsr draw_game_info
        jsr draw_hand
        jsr draw_status
        rts
```

**Step 2: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add src/main.asm
git commit -m "feat: implement main game loop with input handling"
```

---

## Task 19: Player List Display

**Files:**
- Modify: `src/game.asm`

**Step 1: Add player display routine**

Add to `src/game.asm`:

```asm
; Draw player list (rows 2-3)
draw_players:
        ldx #0                  ; Player index
        ldy #2                  ; Start row

.player_loop:
        cpx #MAX_PLAYERS
        beq .done

        ; Check if player exists (has name)
        txa
        asl
        asl
        asl
        asl                     ; x16 for name offset
        tay
        lda PLAYER_NAMES,y
        beq .next_player        ; Empty name = no player

        ; Calculate screen position
        ; 4 players per row, 10 chars each
        txa
        and #$03                ; X mod 4
        asl
        asl
        asl                     ; x8
        adc #1                  ; +1 margin
        tax                     ; X = column

        txa
        pha                     ; Save column

        ; Row 2 for players 0-3, row 3 for 4-7
        lda zp_temp1            ; Current player index
        lsr
        lsr                     ; /4
        clc
        adc #2                  ; Base row
        tay                     ; Y = row

        pla
        tax                     ; Restore column
        jsr screen_goto

        ; Check if current turn
        lda zp_temp1
        cmp zp_current_turn
        bne .no_marker
        lda #'>'
        jsr $ffd2
        bne .print_name
.no_marker:
        lda #' '
        jsr $ffd2

.print_name:
        ; Print name (first 6 chars)
        lda zp_temp1
        asl
        asl
        asl
        asl                     ; x16
        tax
        ldy #0
.name_loop:
        lda PLAYER_NAMES,x
        beq .name_done
        jsr $ffd2
        inx
        iny
        cpy #6
        bne .name_loop

.name_done:
        ; Print card count
        lda #':'
        jsr $ffd2
        ldx zp_temp1
        lda PLAYER_COUNTS,x
        jsr print_number

        ; Closing marker if current turn
        lda zp_temp1
        cmp zp_current_turn
        bne .no_close_marker
        lda #'<'
        jsr $ffd2

.no_close_marker:
.next_player:
        inc zp_temp1
        ldx zp_temp1
        jmp .player_loop

.done:
        rts

; Print single digit number (0-99)
; Input: A = number
print_number:
        cmp #10
        bcc .single_digit
        ; Two digits
        ldx #0
.tens_loop:
        cmp #10
        bcc .print_tens
        sbc #10
        inx
        bne .tens_loop
.print_tens:
        pha
        txa
        clc
        adc #'0'
        jsr $ffd2
        pla
.single_digit:
        clc
        adc #'0'
        jsr $ffd2
        rts
```

**Step 2: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add src/game.asm
git commit -m "feat: add player list display"
```

---

## Task 20: Game Info and Status Display

**Files:**
- Modify: `src/game.asm`

**Step 1: Add game info display**

Add to `src/game.asm`:

```asm
; Draw game info line (row 12)
draw_game_info:
        ldx #5
        ldy #12
        jsr screen_goto

        ; Deck count
        lda #<txt_deck
        sta zp_ptr1
        lda #>txt_deck
        sta zp_ptr1+1
        jsr screen_print

        lda DECK_COUNT
        jsr print_number

        ; Pending draws
        lda PENDING_DRAWS
        beq .no_pending

        lda #' '
        jsr $ffd2
        jsr $ffd2

        lda #<txt_pending
        sta zp_ptr1
        lda #>txt_pending
        sta zp_ptr1+1
        jsr screen_print

        lda #'+'
        jsr $ffd2
        lda PENDING_DRAWS
        jsr print_number

.no_pending:
        rts

txt_deck:
        !text "DECK: "
        !byte 0

txt_pending:
        !text "PENDING: "
        !byte 0

; Draw status line (row 24)
draw_status:
        ldx #0
        ldy #24
        jsr screen_goto

        ; Check if our turn
        lda zp_current_turn
        cmp zp_my_index
        bne .not_turn

        lda #<txt_your_turn
        sta zp_ptr1
        lda #>txt_your_turn
        sta zp_ptr1+1
        jsr screen_print
        rts

.not_turn:
        lda #<txt_waiting
        sta zp_ptr1
        lda #>txt_waiting
        sta zp_ptr1+1
        jsr screen_print
        rts

txt_your_turn:
        !text "YOUR TURN - SELECT CARDS AND PRESS P"
        !byte 0

txt_waiting:
        !text "WAITING FOR OTHER PLAYERS..."
        !byte 0

; Show error from ERROR message
show_error:
        ldx #0
        ldy #24
        jsr screen_goto

        lda #<txt_error
        sta zp_ptr1
        lda #>txt_error
        sta zp_ptr1+1
        jsr screen_print

        ; Error code at payload+0
        lda SERIAL_RX_BUF+PAYLOAD_START
        jsr print_number
        rts

txt_error:
        !text "ERROR CODE: "
        !byte 0

; Show winner
show_winner:
        ldx #10
        ldy #12
        jsr screen_goto

        lda #<txt_winner
        sta zp_ptr1
        lda #>txt_winner
        sta zp_ptr1+1
        jsr screen_print
        rts

txt_winner:
        !text "GAME OVER!"
        !byte 0
```

**Step 2: Build and verify**

Run: `make`
Expected: Builds without errors

**Step 3: Commit**

```bash
git add src/game.asm
git commit -m "feat: add game info and status line display"
```

---

## Task 21: Integration Test - Full Build

**Files:**
- All source files

**Step 1: Verify full build**

Run: `make clean && make`
Expected: Clean build with no errors, `build/rachel.prg` created

**Step 2: Test in VICE (standalone)**

Run: `make run`
Expected:
- Blue screen appears
- Title "RACHEL V1.0" displayed
- Modem initialization message shows
- IP prompt appears
- Can type IP address
- Shows "CONNECTING..." (will fail without server)

**Step 3: Document any issues found**

Create `KNOWN_ISSUES.md` if needed.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: complete initial C64 client implementation"
```

---

## Task 22: Network Integration Test

**Files:**
- None (testing only)

**Step 1: Start iOS host**

- Open RachelApp on iOS/macOS
- Start hosting a TCP game

**Step 2: Launch VICE with network bridge**

Run: `make test-net`

**Step 3: Test connection flow**

1. Enter iOS host IP address (e.g., `192.168.1.100:19840`)
2. Verify "CONNECTING..." appears
3. Verify connection succeeds (WELCOME received)
4. Verify game screen displays
5. Verify player can select cards and play

**Step 4: Document results**

Note any issues for follow-up tasks.

---

## Summary

This implementation plan covers:

1. **Bootstrap** (Tasks 1-3): Minimal PRG, memory map, buffers
2. **Display** (Tasks 4-5): Screen module, title, frame
3. **Input** (Task 6): Keyboard handling
4. **Serial** (Tasks 7-8): User Port, AT commands
5. **Protocol** (Tasks 9-14): RUBP message building and parsing
6. **Game** (Tasks 15-20): Card display, player list, game info
7. **Integration** (Tasks 21-22): Full build and network testing

Each task follows TDD principles where applicable and includes specific commit points for incremental progress.
