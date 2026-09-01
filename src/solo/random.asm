; =============================================================================
; SOLO DETERMINISTIC RANDOMNESS
; =============================================================================
; xorshift64, byte-for-byte the same algorithm the VIC-20 kernel runs, so the
; same seed deals the same game on both machines. State is little-endian.

; -----------------------------------------------------------------------------
; Replace an all-zero seed, which xorshift can never leave.
; -----------------------------------------------------------------------------
sk_seed_normalize:
        lda #0
        ldx #7
.rsn_check:
        ora SK_RANDOM_SEED,x
        dex
        bpl .rsn_check
        bne .rsn_done
        lda #$ef
        sta SK_RANDOM_SEED
        lda #$be
        sta SK_RANDOM_SEED+1
        lda #$ad
        sta SK_RANDOM_SEED+2
        lda #$de
        sta SK_RANDOM_SEED+3
.rsn_done:
        rts

; -----------------------------------------------------------------------------
; x ^= x<<13; x ^= x>>7; x ^= x<<17
; -----------------------------------------------------------------------------
sk_rng_next:
        lda #13
        jsr sk_rng_shift_left
        lda #7
        jsr sk_rng_shift_right
        lda #17
        jmp sk_rng_shift_left

; A = bit count. Copy the state aside, shift the copy, XOR it back in.
sk_rng_shift_left:
        tay
        jsr sk_rng_copy_scratch
; Unrolled because the shift chains through the carry, and any loop counter
; comparison (cpx/cpy) would clear it mid-word. dey alone is safe.
.rsl_bits:
        clc
        rol SK_SCRATCH
        rol SK_SCRATCH+1
        rol SK_SCRATCH+2
        rol SK_SCRATCH+3
        rol SK_SCRATCH+4
        rol SK_SCRATCH+5
        rol SK_SCRATCH+6
        rol SK_SCRATCH+7
        dey
        bne .rsl_bits
        jmp sk_rng_xor_scratch

sk_rng_shift_right:
        tay
        jsr sk_rng_copy_scratch
.rsr_bits:
        clc
        ror SK_SCRATCH+7
        ror SK_SCRATCH+6
        ror SK_SCRATCH+5
        ror SK_SCRATCH+4
        ror SK_SCRATCH+3
        ror SK_SCRATCH+2
        ror SK_SCRATCH+1
        ror SK_SCRATCH
        dey
        bne .rsr_bits
        jmp sk_rng_xor_scratch

sk_rng_copy_scratch:
        ldx #7
.rcs_loop:
        lda SK_RANDOM_SEED,x
        sta SK_SCRATCH,x
        dex
        bpl .rcs_loop
        rts

sk_rng_xor_scratch:
        ldx #7
.rxs_loop:
        lda SK_RANDOM_SEED,x
        eor SK_SCRATCH,x
        sta SK_RANDOM_SEED,x
        dex
        bpl .rxs_loop
        rts

; -----------------------------------------------------------------------------
; A = divisor (2-52) -> A = the 64-bit state modulo that divisor.
; Long division a bit at a time, most significant byte first.
; -----------------------------------------------------------------------------
sk_rng_mod:
        sta sk_mod_divisor
        lda #0
        sta sk_mod_remainder
        ldx #7
.rmd_byte:
        lda SK_RANDOM_SEED,x
        sta sk_mod_source
        ldy #8
.rmd_bit:
        asl sk_mod_source
        rol sk_mod_remainder
        lda sk_mod_remainder
        cmp sk_mod_divisor
        bcc .rmd_next
        sec
        sbc sk_mod_divisor
        sta sk_mod_remainder
.rmd_next:
        dey
        bne .rmd_bit
        dex
        bpl .rmd_byte
        lda sk_mod_remainder
        rts

sk_mod_divisor:   !byte 0
sk_mod_remainder: !byte 0
sk_mod_source:    !byte 0
