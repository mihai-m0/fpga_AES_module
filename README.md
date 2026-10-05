# AES-128 in VHDL — Sequential and Pipelined Implementations

A from-scratch, synthesizable VHDL implementation of the AES-128 block cipher, built as an FPGA project to explore hardware datapath design, finite state machines, and the tradeoffs between latency and throughput in digital design. Verified both in simulation and on real hardware (Digilent Nexys A7-100T), driven over a UART link from a host PC.

The repository contains two encryption cores — a **sequential** version (one round of logic, reused across 10 clock cycles) and a **pipelined** version (ten physical copies of the round logic, operating on ten different blocks simultaneously) — plus the UART infrastructure used to exercise the design on actual silicon.

## Overview

- **Block size:** 128 bits
- **Key size:** 128 bits (AES-128, 10 rounds)
- **Two core architectures**, sharing the same key schedule, S-box, and round-transform logic:
  - `aes_module.vhd` — sequential, FSM-driven, one round per clock cycle, one block in flight at a time
  - `aes_module_pipelined.vhd` — fully pipelined, ten blocks in flight simultaneously once the pipeline is full
- **Host interface:** UART (9600 baud, 8N1), via `receiver.vhd` / `transmitter.vhd` and a top-level glue module (`aes_uart_top.vhd`)
- **Verified on hardware:** Nexys A7-100T, encrypting the official FIPS-197 test vector end-to-end over a serial link

## Architecture — Sequential Core (`aes_module.vhd`)

Driven by a 4-state FSM:

```
idle → round_0 → round_i (×10, one round per clock cycle) → done → idle
```

- **`idle`** — waits for a `start` pulse before beginning encryption.
- **`round_0`** — performs the initial `AddRoundKey` (plaintext XOR with the first round key), before any round transformations.
- **`round_i`** — executes one full AES round per clock cycle (SubBytes → ShiftRows → MixColumns → AddRoundKey), tracked internally via a round counter. MixColumns is correctly omitted on the final (10th) round, per the AES specification.
- **`done`** — latches the final ciphertext onto `encrypted_text` for one clock cycle before returning to `idle`.

One block takes approximately 13 clock cycles from `start` to a valid `encrypted_text`. Only one block can be in flight at a time — a new block cannot begin until the previous one reaches `done`.

## Architecture — Pipelined Core (`aes_module_pipelined.vhd`)

Replaces the FSM entirely with an 11-stage register pipeline (`pipe_reg(0)` through `pipe_reg(10)`), each stage holding a 128-bit value and a `valid` bit:

- **`pipe_reg(0)`** is loaded directly from `text_in xor round_key_0`, gated by `start`, whenever a new block enters.
- **Stages 1 through 10** each instantiate the same combinational round-transform function (`aes_round`), reading the previous stage's register and writing their own on every clock edge. All ten stages execute in parallel, every cycle, each working on a different in-flight block.
- **`encrypted_text`** / **`done_out`** are driven directly from `pipe_reg(10)` — no separate "done" state is needed, since a stage's `valid` bit traveling through the pipe is itself the completion signal.

A new plaintext block can be accepted on every single clock cycle. After an initial ~11-cycle pipeline fill, a finished ciphertext is produced on every subsequent cycle — roughly a 13x throughput improvement over the sequential core, using the same round logic, replicated ten times in hardware rather than reused sequentially. This is a genuine latency-for-throughput trade: per-block latency is unchanged (still ~11 cycles through the pipe), but many blocks can be mid-flight simultaneously.

Both cores share the same `s_box`, key-schedule (`g_func`, Rcon table), `xtime`/`mul3`/`mix_columns`, and `bytes_to_matrix`/`matrix_to_bytes` logic — only the control structure around the round transform differs.

## Shared Building Blocks

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

## UART / Hardware Integration (`aes_uart_top.vhd`)

A top-level module wires the pipelined AES core to the board's USB-UART bridge, so the design can be exercised from a PC over a serial link rather than only in simulation:

- **`receiver.vhd`** — a standard UART receiver: double-flops the incoming line for metastability protection, re-validates the start bit at mid-bit-period to reject glitches, samples each data bit at mid-bit-period, and pulses `valid` for one cycle per received byte.
- **`transmitter.vhd`** — a standard UART transmitter: shifts a byte out start-bit/8-data-bits/stop-bit on request, pulsing `done` when the frame completes.
- **Framing protocol:** the host sends the 16-byte key once, followed by one or more 16-byte plaintext blocks. Each complete plaintext block triggers the AES core; each finished ciphertext is streamed back out over UART, 16 bytes at a time.
- **Baud rate:** 9600, derived from the Nexys A7's 100 MHz system clock (`tick_limit = 10417`).

Note: UART at 9600 baud (~33 ms per 128-bit block transferred) is far slower than the pipelined core's internal throughput (one block per 10 ns at 100 MHz), so the serial link — not the AES core — is the bottleneck in this demonstration setup. The pipelined core's throughput advantage is a property of the core itself, measurable on-chip or relevant in any application where the core is fed at or near full clock speed, rather than through this UART interface.

## Verification

### Simulation

Both cores are verified in simulation against the official AES-128 test vector published in FIPS-197:

- Plaintext: `00112233445566778899aabbccddeeff`
- Key: `000102030405060708090a0b0c0d0e0f`
- Expected ciphertext: `69c4e0d86a7b0430d8cdb78070b4c55a`

via a dedicated testbench (`AES_tb.vhd`), which also exercises the pipelined core's streaming behavior by feeding multiple blocks back-to-back and confirming `done_out` holds for consecutive clock cycles once the pipeline fills.

### Hardware

The full system — pipelined AES core plus UART glue — was synthesized, implemented, and programmed onto a **Digilent Nexys A7-100T**, then exercised from a host PC using a Python (`pyserial`) script sending the same FIPS-197 key and plaintext bytes over the physical UART link.

```
Received:  69c4e0d86a7b0430d8cdb78070b4c55a
Expected:  69c4e0d86a7b0430d8cdb78070b4c55a
```

This confirms correct operation end-to-end: host software → UART transmission → on-chip UART reception and framing → AES key schedule and pipelined encryption → UART transmission back → host software, entirely on real hardware.

## Design Notes

- **Variables vs. signals:** intermediate per-cycle computation (byte substitution, row shifting, column mixing) is performed using process **variables**, which update immediately within a process execution, avoiding the deferred-update pitfalls of signal assignments in sequential logic. Final results are written to **signals** exactly once per state/stage, at the point they should become externally visible.
- **Index convention:** all vectors use ascending (`0 to N`) ranges throughout, with index 0 as the most significant bit/byte, for consistency across the module.
- **Shared key, streamed blocks:** the pipelined core and UART framing both assume a single key is loaded once and reused across many plaintext blocks — the standard real-world AES usage pattern, and the one that makes pipelining meaningful in the first place.

## Roadmap

- [x] Sequential AES-128 core (round-based FSM, 1 round/cycle)
- [x] Fully pipelined AES-128 core (10 concurrent pipeline stages, 1 block/cycle sustained throughput after pipeline fill)
- [x] UART host interface and top-level integration
- [x] Verified on real hardware (Nexys A7-100T) against the FIPS-197 test vector
- [ ] On-chip cycle-accurate throughput measurement (removing UART as the bottleneck)
- [ ] LED visualization of pipeline occupancy (multiple in-flight blocks shown simultaneously)

## Files

| File | Description |
|---|---|
| `aes_module.vhd` | Sequential AES-128 encryption core |
| `aes_module_pipelined.vhd` | Pipelined AES-128 encryption core (10 concurrent stages) |
| `aes_uart_top.vhd` | Top-level module: UART host interface wired to the pipelined AES core |
| `receiver.vhd` | UART receiver |
| `transmitter.vhd` | UART transmitter |
| `AES_tb.vhd` | Testbench, verified against the FIPS-197 test vector (both cores) |
| `Nexys-A7-100T-Master.xdc` | Board constraints (clock + UART pins only; all other I/O left unconstrained) |
