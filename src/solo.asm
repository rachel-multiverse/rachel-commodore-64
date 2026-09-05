; =============================================================================
; SOLO MODE
; =============================================================================
; A complete standalone game: local rules, local opponents, no host and no
; network. Permitted by decision 0006 for the full 2-8 player range the rules
; define.
;
; The kernel below is the C64's own. It is not consulted by the online path,
; which remains render-only with the host authoritative (decision 0003).

        !source "src/solo/state.asm"
        !source "src/solo/random.asm"
        !source "src/solo/hands.asm"
        !source "src/solo/deck.asm"
        !source "src/solo/rules.asm"
        !source "src/solo/turn.asm"
        !source "src/solo/ai.asm"
        !source "src/solo/game.asm"
!if SOLO_SELFTEST {
        !source "src/solo/selftest.asm"
}

; -----------------------------------------------------------------------------
; Seed the deal from whatever the machine can offer that a player cannot
; predict: the jiffy clock has been running since power-on, and the raster line
; is wherever the beam happens to be when the last key was pressed.
; Clobbers: A, X.
; -----------------------------------------------------------------------------
solo_seed_from_machine:
        lda $a0                 ; jiffy clock, high
        sta SK_RANDOM_SEED
        lda $a1
        sta SK_RANDOM_SEED+1
        lda $a2                 ; jiffy clock, low - moves 60 times a second
        sta SK_RANDOM_SEED+2
        lda $d012               ; raster line
        sta SK_RANDOM_SEED+3
        lda $dc04               ; CIA #1 timer A, free-running
        sta SK_RANDOM_SEED+4
        lda $dc05
        sta SK_RANDOM_SEED+5
        lda $d41b               ; SID oscillator 3, noise when voice 3 is set
        sta SK_RANDOM_SEED+6
        lda $a2
        eor $d012
        sta SK_RANDOM_SEED+7
        rts

; -----------------------------------------------------------------------------
; Ask how many seats are at the table. Anything outside 2-8 is ignored rather
; than clamped, so a mistyped key cannot silently start the wrong game.
; Out: A = seat count. Clobbers: A, X, Y.
; -----------------------------------------------------------------------------
solo_ask_players:
        lda #$93                ; clear screen
        jsr CHROUT
        ldx #4
        ldy #10
        lda #<txt_solo_players
        sta zp_ptr1
        lda #>txt_solo_players
        sta zp_ptr1+1
        jsr screen_print_at
.sask_wait:
        jsr GETIN
        cmp #'2'
        bcc .sask_wait
        cmp #'9'                ; one past '8'
        bcs .sask_wait
        pha
        jsr CHROUT
        pla
        sec
        sbc #'0'
        rts

; -----------------------------------------------------------------------------
; The game is over: the seat still holding cards finishes last.
; -----------------------------------------------------------------------------
solo_show_result:
        ; Find the survivor for the shared result renderer.
        ldx #0
.sres_find:
        txa
        jsr sk_seat_is_out
        beq .sres_found
        inx
        cpx SK_PLAYER_COUNT
        bcc .sres_find
        ldx #0
.sres_found:
        stx WINNER_INDEX
        jsr draw_result
        jmp input_wait_key

txt_solo_players:
        !text "PLAYERS AT THE TABLE (2-8)? "
        !byte 0
txt_solo_over:
        !text "GAME OVER - "
        !byte 0
txt_solo_won:
        !text "YOU WENT OUT. PRESS A KEY."
        !byte 0
txt_solo_lost:
        !text "YOU FINISHED LAST. PRESS A KEY."
        !byte 0
