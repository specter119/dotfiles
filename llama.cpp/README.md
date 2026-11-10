# llama-server — Qwen3.8-27B UD-Q4_K_XL (RTX PRO 4500 Blackwell, 32 GB)

Local OpenAI-compatible API server for Qwen3.8-27B, quantized with
unsloth Dynamic V3.0 (UD-Q4_K_XL, 17.6 GB), running on a single
RTX PRO 4500 Blackwell via llama.cpp CUDA. All agents/tools point at
`http://127.0.0.1:8080/v1`.

## Hardware and why this config looks like this

|                    | Old box (retired)            | This box                                   |
| ------------------ | ---------------------------- | ------------------------------------------ |
| GPU                | 2× RTX 2080 Ti, 22 GB each   | 1× RTX PRO 4500 Blackwell (GB203), 32 GB   |
| Compute capability | sm_75 (Turing)               | sm_120 (Blackwell)                         |
| Memory bandwidth   | ~616 GB/s each, NVLink       | 896 GB/s (GDDR7, 256-bit)                  |
| Tensor cores / TDP | 2× 544 / 2× 250 W            | 328 / 200 W                                |
| Interconnect       | NVLink, `--split-mode layer` | single GPU, no split flags                 |
| Host               | native Linux                 | WSL2 guest, driver from `/usr/lib/wsl/lib` |

The old unit was tuned for two bandwidth-starved cards: layer split, 2 slots ×
16K, `--spec-draft-p-min 0.75` to keep MTP verification cheap. None of that
transfers. What changed:

- **Multi-GPU flags are gone.** `--split-mode` / `--tensor-split` / `--main-gpu`
  only apply with more than one device; on one GPU they are noise.
- **Context went from 32K to 256K.** One card holds the whole model plus a big
  KV pool, so the 2×16K split is no longer a VRAM constraint.
- **Quant moved IQ4_XS → UD-Q4_K_XL.** 32 GB buys a higher-quality quant at the
  same context; the old file name (`Qwen3.8-27B-IQ4_XS.gguf`) no longer exists
  upstream, which is why the sync script is pinned to the current name.
- **KV cache is `q8_0` for both K and V.** 256K of f16 KV does not fit next to
  17.6 GB of weights; `q8_0` halves it at negligible quality cost.
- **MTP stays on, but ungated.** `p-min 0.75` was tuned for a card where every
  verification pass cost a full weight read. This GPU has ~1.5× the bandwidth of
  one 2080 Ti, so the gate is pure loss here: measured 51.5 t/s gated vs 70 t/s
  ungated on the same prompt. See [Measured](#measured-on-this-card).
- **`--fit on`** lets llama.cpp place what is left after the explicit
  `-c` / `-ngl` and warn instead of OOM-killing the service.

Bandwidth ceiling for this card: 896 GB/s ÷ 17.6 GB of weights ≈ **51 tok/s** of
pure single-stream decode before any batching or speculation. Anything close to
that is the card working as designed; MTP is what pushes past it.

## Layout

| Path                                                          | What                                                         |
| ------------------------------------------------------------- | ------------------------------------------------------------ |
| `~/.config/systemd/user/llama-server.service`                 | systemd user unit                                            |
| `~/.local/lib/qwen38-model-sync.sh`                           | model ensure/verify/update script                            |
| `~/.cache/huggingface/hub/models--unsloth--Qwen3.8-27B-GGUF/` | model cache (huggingface default dir, `hf`/`hfd` compatible) |

## Usage

```bash
systemctl --user daemon-reload
systemctl --user enable --now llama-server   # start + autostart on login
systemctl --user status llama-server          # logs via: journalctl --user -u llama-server -f
curl http://127.0.0.1:8080/v1/models          # health / model check
curl http://127.0.0.1:8080/metrics            # prometheus metrics (--metrics)
```

Point any OpenAI-compatible client at `http://127.0.0.1:8080/v1`,
model id as shown by `/v1/models` (typically the GGUF filename).

## Model management

- **Auto-download**: on every start, `ExecStartPre` runs the sync script. A
  complete file (size matches the HF API for this revision) exits 0 without
  network; a missing or truncated file is fetched with `aria2c` (8 connections,
  resumable) from `HF_ENDPOINT` (default `https://hf-mirror.com`) and checked
  against the sha256 the API reports.
- **Verify**: `~/.local/lib/qwen38-model-sync.sh verify`
- **Force update** (e.g. upstream republished the quant):
  `~/.local/lib/qwen38-model-sync.sh update && systemctl --user restart llama-server`
- **Vision projector** (optional, +0.9 GB VRAM):
  `~/.local/lib/qwen38-model-sync.sh mmproj`, then add
  `--mmproj <same dir>/mmproj-F16.gguf` to the unit and restart. Without it,
  `--image-max-tokens` is inert.

## Serving config

The unit runs:

```
--n-gpu-layers all                     # single GPU, everything resident
--ctx-size 262144 --parallel 2 --kv-unified
--flash-attn on --cache-type-k q8_0 --cache-type-v q8_0
--batch-size 2048 --ubatch-size 1024
--fit on --fit-target 2048
--spec-type draft-mtp --spec-draft-n-max 4 --spec-draft-p-min 0
--cache-ram -1 --ctx-checkpoints 16
--metrics --jinja --reasoning-preserve --reasoning-budget 2000
--chat-template-kwargs '{"reasoning_effort": "low"}' --image-max-tokens 4000
```

| Flag                                               | Why                                                                                                                                                                            |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--n-gpu-layers all`                               | One 32 GB card holds all 64 layers; no offload, no PCIe traffic per token.                                                                                                     |
| `--ctx-size 262144`                                | The model's native window. KV cost is small because only 16 of 64 layers are full attention (every 4th; the rest are Gated-DeltaNet linear attention with a fixed-size state). |
| `--parallel 2 --kv-unified`                        | Two agent requests in flight share one 256K pool instead of reserving 128K each. A single long session can still use the whole window.                                         |
| `--flash-attn on`                                  | Required for the MTP numbers below and for long context without a quadratic attention buffer.                                                                                  |
| `--cache-type-k/v q8_0`                            | 256K of f16 KV is ~16 GB; `q8_0` is ~8.7 GB. Measured cost elsewhere is ~0–3%.                                                                                                 |
| `--batch-size 2048 --ubatch-size 1024`             | Prefill is compute-bound and Blackwell has the headroom; a bigger micro-batch buys prompt-processing speed. Drop `-ub` to 512 if VRAM gets tight.                              |
| `--fit on --fit-target 2048`                       | Safety net, not an active knob: `--fit` only adjusts *unset* arguments, so with explicit `-ngl all` it logs `failed to fit params ... abort` (harmless) and does nothing. It is kept so that dropping `-c` later still gets a placement that leaves 2 GB free. |
| `--spec-type draft-mtp`                            | Qwen3.8 ships MTP heads; the unsloth GGUF carries the `nextn` tensors. Biggest single decode win.                                                                              |
| `--spec-draft-n-max 4 --spec-draft-p-min 0` | Ungated n4. Measured below: the `p-min` gate costs 26% here, and n6 is slower than n4. |
| `--cache-ram -1`                                   | 78 GB of host RAM: keep every idle slot's prompt cached so resuming an agent session skips prefill.                                                                            |
| `--ctx-checkpoints 16`                             | Lets a client rewind/truncate context without re-prefilling from zero.                                                                                                         |
| `--reasoning-budget 2000` + `reasoning_effort low` | Soft + hard cap on thinking so short answers don't burn the token budget (client-side `enable_thinking` is not forwarded by llama.cpp's OpenAI layer).                         |

### VRAM budget (262144 tokens, q8_0 KV)

`nvidia-smi` reports **29968 MiB used of 32623 MiB** once the server is up with
this unit — 2.6 GB of headroom, which is why `--ubatch-size 2048` was rejected
(it pushed usage to 31414 MiB for no prefill gain).

| Item                                                           | Size          |
| -------------------------------------------------------------- | ------------- |
| Weights (UD-Q4_K_XL)                                           | 17.6 GB       |
| KV, 16 full-attention layers × 4 kv heads × 256 head_dim, q8_0 | ~8.7 GB       |
| Linear-attention state (48 layers, f32)                        | ~0.2 GB       |
| Compute buffers (ubatch 1024) + CUDA context                   | ~1.5–2 GB     |
| **Measured total**                                             | **29.3 GB** |

Quant/context alternatives that also fit:

| Weights            | Context | KV   | Note                                     |
| ------------------ | ------- | ---- | ---------------------------------------- |
| UD-Q4_K_XL 17.6 GB | 262144  | q8_0 | default, best context/quality balance    |
| UD-Q5_K_M 19.8 GB  | 131072  | q8_0 | ~+1 GB weights, half the window          |
| UD-IQ4_XS 14.3 GB  | 262144  | f16  | max KV precision, lower weight precision |

## Measured on this card

Measured 2026-11-10, llama.cpp 0.9.0 (b12110, `sm_120a`), UD-Q4_K_XL, 262144
ctx / 2 slots / q8_0 KV, 2671-token chat prompt, 600 generated tokens,
temperature 0. `tg` is decode, `pp` is prefill.

| Speculative setting | tg t/s | draft acceptance |
| ------------------- | -----: | ---------------: |
| none | 39.5 | — |
| MTP n4, `p-min 0.75` (gated) | 51.5 | 0.88 |
| MTP n6, `p-min 0.75` (gated) | 47.7 | 0.82 |
| MTP n6, `p-min 0` (ungated) | 62.3 | 0.33 |
| **MTP n4, `p-min 0` (ungated)** | **88–89** | 0.71 |

Other numbers from the same run:

| Scenario | Result |
| --- | --- |
| prefill, cold 2.7K prompt | ~1286 t/s |
| prefill, 101K-token prompt | 1034 t/s (99 s), 30016 MiB VRAM |
| 2 concurrent requests | 63 + 61 t/s (~124 t/s aggregate) |
| `llama-bench` pp2048 / tg256, no spec | 2077 / 41.8 t/s |

Two things this card taught us that the old 2080 Ti numbers did not:

- **The `p-min` gate is a loss here.** Gating at 0.75 cut acceptance-free drafting
  and cost 26% (51.5 vs 70 t/s on the same prompt). Drafting is one extra 1-layer
  forward; on a card with 896 GB/s it is cheaper than the verification it saves.
- **n6 is worse than n4.** More drafts per step means more rejected tokens to
  verify; acceptance fell from 0.71 to 0.33 and throughput with it.

The 200 W board power limit is the ceiling: sustained decode sits at 199 W, so
numbers drift a few percent with ambient temperature, not with the flags.

## Tuning: what to A/B

Measure before believing any of it — the table above is one prompt, one quant.

```bash
# decode + prefill for the exact file/quant, no server needed
llama-bench -m ~/.cache/huggingface/hub/models--unsloth--Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q4_K_XL.gguf \
  -ngl 99 -fa on -ctk q8_0 -ctv q8_0 -p 2048 -n 256 -r 3

# end-to-end: real prefill/decode timings from the API
curl -s http://127.0.0.1:8080/v1/completions -H 'content-type: application/json' \
  -d '{"prompt":"<20k-token prompt>","max_tokens":1}' | jq '.timings'

# MTP acceptance rate (the number that decides n-max / p-min)
journalctl --user -u llama-server -f | grep -i "draft acceptance"
```

Knobs, in order of expected payoff:

1. **`--spec-draft-n-max` / `--spec-draft-p-min`.** Already swept: n4 ungated is
   the winner on this card. Re-sweep if you change quant or run a different
   workload — acceptance is content-dependent (0.50 on plain prose, 0.71 on the
   unit's chat template, 0.88 on repetitive text).
2. **`--ubatch-size`.** 512 → 1024 → 2048 against a realistic 20K prompt.
   Measured: 1024 and 2048 are within 0.5% on prefill (1690 vs 1684 t/s) while
   2048 costs 1.4 GB of VRAM. Stay at 1024.
3. **`--parallel`.** `1` for honest single-stream numbers, `2` for agent use
   (measured 124 t/s aggregate), `4` only if you actually run four requests at
   once — MTP's advantage fades as slots batch up.
4. **`--cache-type-k/v`.** `q8_0` is the default here. `f16` if you drop to
   ≤128K context and want maximum fidelity; `q4_0` only if you need more window
   than 256K.
5. **`--cache-ram`.** `-1` keeps all idle prompts in host RAM. Lower it only if
   the host starts swapping.

## Build (nix-packages flake)

The binary comes from `~/Documents/github.repos/nix-packages#llama-cpp`, a
`llama-cpp` override with `cudaSupport = true`.

- **Architecture must be `sm_120`.** The previous build used
  `cudaCapabilities = [ "7.5" ]`, i.e. `CMAKE_CUDA_ARCHITECTURES=75`. On
  Blackwell that binary has no compatible SASS and only runs through PTX JIT
  from `compute_75`, which is both slower to start and slower per token. The
  flake now sets `cudaCapabilities = [ "12.0" ]`; ggml rewrites a plain `12X`
  to `12Xa` (Blackwell FP4 tensor cores are arch-specific), so `"12.0"` is the
  whole story.
- **It cannot be auto-detected.** Nix builds are sandboxed without
  `/dev/nvidia*`: the configure log of this very build says
  `CMAKE_CUDA_ARCHITECTURES_NATIVE=No CUDA devices found`. `native` would probe
  the build host (or fail), not the machine that runs the result. The capability
  list is a per-machine declaration; a Turing host would set `[ "7.5" ]`, a
  mixed fleet would list both (at the cost of a longer build).
- **WSL driver.** The CUDA libraries carry `RUNPATH /run/opengl-driver/lib`,
  which only exists on NixOS. The flake wraps every binary with
  `LD_LIBRARY_PATH=/usr/lib/wsl/lib` so ggml finds the Windows driver's
  `libcuda.so.1`. Do not install a Linux display driver in WSL.

```bash
cd ~/Documents/github.repos/nix-packages
nix flake update          # llama.cpp 0.4.1 (b10964) -> 0.9.0 (b12110)
nix build .#llama-cpp     # ~20-40 min, local build: sm_120 is not in the cache
nix profile upgrade llama-cpp
```

The profile entry is installed from the *unlocked* flake reference (`git+file://`
without a rev), so `nix profile upgrade llama-cpp` re-evaluates the working tree
and picks up both the arch change and any later `nix flake update`.

Verify the arch actually landed (the CMake line is echoed during configure):

```bash
nix log ~/Documents/github.repos/nix-packages#llama-cpp 2>/dev/null \
  | grep -m1 "Using CMAKE_CUDA_ARCHITECTURES"
# expect ...=120a, not 75
```

## Known trade-offs

- **MTP is single-stream.** The gain shrinks as `--parallel` batches more slots;
  it is worth it at 1–2 slots, marginal at 4.
- **Hybrid attention keeps long context cheap.** Only 16/64 layers grow a KV
  cache, which is why 256K fits in 32 GB at all. Do not copy this budget to a
  dense model.
- **`q8_0` KV is a fit decision, not a speed decision.** It exists to make 256K
  possible; at ≤128K, f16 is within noise.
- **`--reasoning-budget 2000`** is a hard cap. Long reasoning tasks will be cut;
  raise it per client with `max_tokens` or edit the unit.
