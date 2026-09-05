; =============================================================================
; NETWORK TRANSPORT DISPATCH
; =============================================================================

TRANSPORT_USERPORT = 0
TRANSPORT_ULTIMATE = 1

; Set once the peer has closed the connection. Only the Ultimate transport can
; tell directly. The shared liveness check detects silence on the user port,
; which has no carrier-detect signal wired.
transport_link_down:
        !byte 0

transport_init:
        lda #0
        sta transport_link_down
        jsr ultimate_detect
        bne ti_userport
        lda #TRANSPORT_ULTIMATE
        sta zp_transport
        lda #0
        sta zp_rx_head
        rts
ti_userport:
        lda #TRANSPORT_USERPORT
        sta zp_transport
        jsr serial_init
        jmp serial_rx_init

; Input: zp_ptr1 -> HOST:PORT. Returns A=0 on success.
transport_connect:
        lda zp_transport
        beq tc_modem
        jmp ultimate_connect
tc_modem:
        ; Zimodem resets to command mode before every new connection. That reset
        ; points zp_ptr1 at its own command string and never puts it back, so
        ; the caller's HOST:PORT has to be parked across the call — otherwise
        ; the dial that follows walks whatever the reset left behind.
        lda zp_ptr1
        sta tc_saved_ptr
        lda zp_ptr1+1
        sta tc_saved_ptr+1
        jsr modem_reset
        cmp #0
        bne tc_failed
        jsr delay_250ms
        lda tc_saved_ptr
        sta zp_ptr1
        lda tc_saved_ptr+1
        sta zp_ptr1+1
        jmp modem_dial
tc_failed:
        lda #1
        rts

tc_saved_ptr:
        !byte 0, 0

transport_send_frame:
        lda zp_transport
        beq tsf_serial
        jmp ultimate_send_frame
tsf_serial:
        ; The receive interrupt has nothing to do while we are driving the
        ; line, and letting it fire mid-frame would cost transmit timing.
        jsr serial_rx_disable
        sei                     ; One frame, one uninterrupted burst.
        ldx #0
tsf_tx_loop:
        lda SERIAL_TX_BUF,x
        jsr serial_send_byte
        inx
        cpx #RUBP_MSG_SIZE
        bne tsf_tx_loop
        cli
        jsr serial_rx_enable
        lda #0
        rts

transport_available:
        lda zp_transport
        beq ta_serial
        jmp ultimate_available
ta_serial:
        jsr serial_rx_ready
        eor #1                  ; transport API: zero means data is available
        rts

transport_receive_frame:
        lda zp_transport
        beq trf_serial
        jmp ultimate_receive_frame
trf_serial:

        ; Resynchronise on the frame magic rather than trusting the stream to
        ; stay aligned. A bit-banged UART loses or gains a byte from time to
        ; time; without this, one lost byte shifts every frame that follows for
        ; the rest of the session, and the client never parses another message
        ; even though the host is talking perfectly. Scanning for "RACH" costs
        ; nothing when the stream is clean and recovers by itself when it is
        ; not.
        ; Bounded, so a stream that dries up mid-scan gives the main loop back
        ; rather than parking the machine in here with interrupts masked.
        lda #64
        sta trf_scan_left

        ldx #0                  ; bytes of the magic matched so far
trf_sync:
        jsr trf_next_byte
        bcc trf_timeout
        cmp rubp_magic,x
        beq trf_advance

        ; No match. The byte may still be the start of the next magic, so try
        ; it against the first letter before giving up on it entirely.
        ldx #0
        cmp rubp_magic
        beq trf_advance
        dec trf_scan_left
        bne trf_sync
        beq trf_timeout
trf_advance:
        sta SERIAL_RX_BUF,x
        inx
        cpx #4
        bcc trf_sync

        ; Header magic in hand; the rest of the frame follows it.
trf_rx_loop:
        jsr trf_next_byte
        bcc trf_timeout
        sta SERIAL_RX_BUF,x
        inx
        cpx #RUBP_MSG_SIZE
        bcc trf_rx_loop
        lda #0
        rts

        ; A frame that never finished arriving is not a frame. Report it as
        ; such and let the caller come back round; the magic scan re-aligns on
        ; whatever arrives next.
trf_timeout:
        lda #1
        rts

trf_scan_left:
        !byte 0

; -----------------------------------------------------------------------------
; Next byte of a frame, from the ring the interrupt handler fills.
; Out: A = byte, C set. C clear when nothing arrived in time.
;
; Reading from the ring rather than the wire is what lets everything above this
; take as long as it likes: bytes keep arriving while the client is drawing.
; Clobbers: A, X
; -----------------------------------------------------------------------------
trf_next_byte:
        lda #<TRF_BYTE_WAIT
        sta trf_wait_lo
        lda #>TRF_BYTE_WAIT
        sta trf_wait_hi
.tnb_poll:
        jsr serial_rx_get
        bcs .tnb_got
        dec trf_wait_lo
        bne .tnb_poll
        dec trf_wait_hi
        bne .tnb_poll
        clc                     ; nothing arrived; caller abandons the frame
        rts
.tnb_got:
        rts

; Roughly a byte time and a half of patience per byte, in poll passes.
TRF_BYTE_WAIT = 1200

trf_wait_lo:
        !byte 0
trf_wait_hi:
        !byte 0

rubp_magic:
        !text "RACH"
