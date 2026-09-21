# AES-128 in VHDL — Sequential Implementation

A from-scratch, synthesizable VHDL implementation of the AES-128 block cipher, built as an FPGA project to explore hardware datapath design, finite state machines, and the tradeoffs between latency and throughput in digital design.

This repository currently contains the **sequential** version of the core (`aes_module.vhd`): a single round-logic datapath reused across 10 clock cycles per block. A **pipelined** version, built to maximize throughput by processing multiple blocks concurrently, is in progress — see the Roadmap section below.

## Overview

`aes_module.vhd` implements AES-128 encryption end-to-end: key expansion, and the full 10-round encryption pipeline (SubBytes, ShiftRows, MixColumns, AddRoundKey), driven by a finite state machine.

- **Block size:** 128 bits
- **Key size:** 128 bits (AES-128, 10 rounds)
- **Architecture:** round-based FSM, one round of the cipher executed per clock cycle
- **Interface:** synchronous, `start`-triggered, single in-flight block at a time

## Architecture

### Finite State Machine

The core is driven by a 4-state FSM:

```
idle → round_0 → round_i (×10, one round per clock cycle) → done → idle
```

- **`idle`** — waits for a `start` pulse before beginning encryption.
- **`round_0`** — performs the initial `AddRoundKey` (plaintext XOR with the first round key), before any round transformations.
- **`round_i`** — executes one full AES round per clock cycle (SubBytes → ShiftRows → MixColumns → AddRoundKey), tracked internally via a round counter. MixColumns is correctly omitted on the final (10th) round, per the AES specification.
- **`done`** — latches the final ciphertext onto `encrypted_text` for one clock cycle before returning to `idle`.

### Key Expansion

The 128-bit input key is expanded into 11 round keys (44 32-bit words total) using the standard AES key schedule, computed combinationally in a dedicated process:

- **RotWord** — cyclic left-rotation of a 32-bit word by one byte.
- **SubWord** — S-box substitution applied independently to each of the 4 bytes in a word.
- **Rcon XOR** — the first byte of each transformed word is XORed with a round-dependent constant, generated from a precomputed round constant table (powers of `x` in GF(2⁸)).

### S-box Substitution

Implemented as a combinational 256-entry lookup table (ROM), rather than computing the GF(2⁸) multiplicative inverse and affine transform at runtime — the substitution values are fixed and public, so a synthesized ROM/LUT lookup is both simpler and faster than live computation.

### State Representation

The 128-bit block is represented internally as a 4×4 byte matrix (row-major array-of-arrays: `array(0 to 3) of array(0 to 3) of std_logic_vector`), matching the standard AES state array layout — byte `i` of the input maps to `state(i mod 4)(i / 4)`. Two conversion functions (`bytes_to_matrix` / `matrix_to_bytes`) translate between this matrix form and the flat 128-bit vector used at the module's I/O boundary.

### ShiftRows

Implemented as a cyclic left-rotation of each matrix row, with the rotation amount equal to the row index (row 0 unshifted, row 1 shifted by 1, ..., row 3 shifted by 3) — achieved via array slicing and concatenation rather than a generalized rotate function.

### MixColumns

Each column of the state is transformed via matrix multiplication in **GF(2⁸)** (the Galois Field used throughout AES), using the fixed MDS (Maximum Distance Separable) matrix specified by the AES standard. Two helper functions implement the required field arithmetic efficiently, without needing general-purpose finite-field multiplication:

- **`xtime`** — multiplication by `x` (i.e. "×2"): a left bit-shift, conditionally XORed with the reduction constant `0x1B` (derived from AES's irreducible polynomial `x⁸ + x⁴ + x³ + x + 1`) when the shift overflows 8 bits.
- **`mul3`** — multiplication by 3, derived from the distributive property (`3 = x + 1`, so `3·b = xtime(b) ⊕ b`).

All arithmetic in this step is field addition (XOR) and field multiplication by small constants (1, 2, 3) — the same construction used in the AES reference specification (FIPS-197).

## Design Notes

- **Latency vs. throughput:** this implementation prioritizes simplicity and a shallow combinational path per clock cycle over raw throughput. One block takes approximately 13 clock cycles from `start` to a valid `encrypted_text` (1 cycle idle→round_0, 1 cycle round_0→round_i, 10 cycles for the round loop, 1 cycle to latch the result in `done`). Only one block can be in flight at a time.
- **Variables vs. signals:** intermediate per-cycle computation (byte substitution, row shifting, column mixing) is performed using process **variables**, which update immediately within a process execution, avoiding the deferred-update pitfalls of signal assignments in sequential logic. Final results are written to **signals** exactly once per state, at the point they should become externally visible.
- **Index convention:** all vectors use ascending (`0 to N`) ranges throughout, with index 0 as the most significant bit/byte, for consistency across the module.

## Verification

The design is verified in simulation against the official AES-128 test vector published in FIPS-197 (plaintext `00112233445566778899aabbccddeeff`, key `000102030405060708090a0b0c0d0e0f`, expected ciphertext `69c4e0d86a7b0430d8cdb78070b4c55a`), via a dedicated testbench (`AES_tb.vhd`).

## Roadmap

- [x] Sequential AES-128 core (round-based FSM, 1 round/cycle)
- [ ] Fully pipelined AES-128 core (10 concurrent pipeline stages, targeting 1 block/cycle sustained throughput after pipeline fill)
- [ ] Throughput benchmarking on target FPGA

## Files

| File | Description |
|---|---|
| `aes_module.vhd` | Sequential AES-128 encryption core |
| `AES_tb.vhd` | Testbench, verified against the FIPS-197 test vector |
