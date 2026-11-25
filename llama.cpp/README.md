# llama-server — Inkling-2-Mini UD-Q4_K_XL (RTX PRO 4500 Blackwell, 32 GB)

Local OpenAI-compatible API server for Thinking Machines Lab's
Inkling-2-Mini, unsloth Dynamic V3 quantised (UD-Q4_K_XL), served by the
Unsloth llama.cpp CUDA build. All agents and tools point at
`http://127.0.0.1:8080/v1`.

Replaced the previous Qwen3.8-27B service on this machine — that model's
weights were deleted, this one is 17.6 GB against 27B's larger footprint.

## What the model is

`inkling2_loop`: 24 blocks, hidden 2304, **128 experts with 8 active**
(`general.size_label = 128x1.8B`), native context 1,048,576. It is a sparse
MoE, which is the whole reason this config looks the way it does: per-token
compute is that of a ~2B dense model while resident weights are those of a
26B-class one, so memory is the binding constraint and throughput is not.

Three consequences follow, and every flag below traces to one of them:

1. **Weights are the memory floor.** 17.6 GB of UD-Q4_K_XL + 639 MB vision
   projector. On a 32 GB card that leaves ~13 GB for KV cache and compute
   buffers — enough for a large context, but not for anything generous on top.
2. **It is a reasoning model.** The chat template emits a
   `Thinking effort level: <num>` system message and defaults to **0.9** when
   the client sends no `reasoning_effort`. That default is expensive (see
   [Reasoning effort](#reasoning-effort)), so the server sets a lower default.
3. **Native context is 1M, the card supports 256K here.** KV size, not model
   capability, decides `--ctx-size`.

## Hardware

|          | Value                                                        |
| -------- | ------------------------------------------------------------ |
| GPU      | RTX PRO 4500 Blackwell, 32 623 MiB VRAM                       |
| Driver   | 597.16, WSL2 (Windows driver only — no CUDA toolkit in Linux) |
| System   | 78 GB RAM, 20 threads                                        |
| Compute  | sm_120 (Blackwell), CUDA 13.3 runtime from the unsloth bundle |

WSL2 supplies `libcuda.so.1` through `/usr/lib/wsl/lib`; the CUDA *runtime*
libraries (`libcudart`, `libcublas`, `libcublasLt`, `libnvJitLink`) are not
present and cannot be apt-installed without root, so the install script unpacks
the pinned NVIDIA redistributables next to the binary. `llama-server` finds them
through the bundle's `$ORIGIN` rpath.

## Install layout

| Path                                                          | What                                                   |
| ------------------------------------------------------------- | ------------------------------------------------------ |
| `~/.local/opt/llama.cpp/<tag>/`                                | one unpacked Unsloth bundle per release tag            |
| `~/.local/opt/llama.cpp/current`                               | symlink the unit resolves through                      |
| `~/.cache/huggingface/hub/models--unsloth--Inkling-2-Mini-GGUF` | the two GGUFs (weights + mmproj) and `.hf-meta.json`   |
| `~/.local/share/llama-server/llama-cpp-install.sh`             | `ensure` / `verify` / `reinstall` / `check` / `path`     |
| `~/.local/share/llama-server/model-sync.sh`                    | `ensure` / `model` / `mmproj` / `verify` / `update`     |
| `~/.config/systemd/user/llama-server.service`                  | the unit                                               |

Both scripts are idempotent and offline-safe: a matching size (and sha256 where
the HF API gives one) short-circuits to exit 0, so a boot with no network still
starts an already-populated directory. Bundle tags are never mutated in place —
`reinstall` stages the new tag beside the target and swaps it atomically.

The two scripts use deliberately different verbs, because the things they
version are different:

| | binary (`llama-cpp-install.sh`) | weights (`model-sync.sh`) |
| --- | --- | --- |
| `ensure` | install the pin if missing | fetch any missing file |
| `verify` | re-check the bundle, print version | re-check all three sha256 |
| `check` | ask GitHub for a newer release, change nothing | — |
| `reinstall` / `update` | re-download the **same** pin | re-fetch **only changed** files |
| `path` | print the binary path | — |

There is no `update <tag>`: a tag typed on the command line would have no pinned
sha256 to verify against. Moving versions is an edit of `TAG` and
`ASSET_SHA256`, then `reinstall`. `model-sync.sh update` is incremental — it
refreshes the HF metadata table and re-downloads only files whose size or sha256
changed, so an unchanged 17.6 GB file costs one API call, not a download.

The Unsloth bundle is **not** self-contained. `tar tzf` of the released
`cuda13-portable` archive lists 61 members, all ggml/llama objects — no
`libcudart`, `libcublas` or `libcublasLt`. `libggml-cuda.so` NEEDs
`libcudart.so.13`, `libcublas.so.13` and `libcublasLt.so.13`, so the runtime
redist downloads are required, not defensive.

## Measured on this card

Every number below comes from this machine, this GPU, this build
(b12649-mix-c7059d6). Raw logs: `/tmp/inkling-work/bench*.jsonl`.

### Context size vs. the VRAM cliff

Prefill is the sensitive signal. A 26 K-token prompt prefills at ~2 100 tok/s
while there is headroom, and collapses when the driver starts oversubscribing
VRAM into host RAM. The cliff is sharp and it is what picks `--ctx-size` and
`--cache-type` (no drafter loaded, ubatch 512 unless noted):

| ctx     | KV   | ubatch | VRAM peak (MiB) | headroom | 26K prefill  |
| ------- | ---- | ------ | --------------- | -------- | ------------ |
| 131 072 | f16  | 512    | 27 628          | 4 995    | 2 090 tok/s  |
| 196 608 | f16  | 512    | 28 257          | 4 366    | 2 139 tok/s  |
| 262 144 | q8_0 | 512    | 27 631          | 4 992    | 2 074 tok/s  |
| **262 144** | **q8_0** | **1024** | **30 084** | **2 539** | **2 175 tok/s** |
| 262 144 | f16  | 512    | 31 642          | 981      | 2 133 tok/s  |
| 262 144 | q8_0 | 512 + drafter | 30 008 | 2 615  | 2 091 tok/s  |
| 262 144 | f16  | 512 + drafter | 32 282 | 341    | **timeout**  |

Three things this table settles:

- **q8_0 KV is worth ~4 GB at 256K**, not a marginal amount: 31 642 → 27 631 MiB,
  for a decode difference inside noise (92.9 vs 90.6 tok/s). That is the whole
  reason it is in the unit.
- **256K with f16 KV technically fits** (981 MiB spare) but sits one allocation
  away from the cliff — adding a drafter at the same context pushed it to
  32 282 MiB and the identical prompt timed out instead of prefilling.
- **ubatch 1024 costs 2.5 GB and buys 10 % prefill** (2 175 vs 2 074 tok/s).
  That is affordable only because q8_0 freed 4 GB first. ubatch 2048 does not
  fit at all and collapses prefill to **78 tok/s**.

### Speculation: DSpark is a regression here, ngram-mod is free

Cold, distinct prompts, 8 samples, A/B/A server order to rule out drift
(256K / q8_0 / ubatch 512):

| variant                 | median decode | at depth | VRAM peak |
| ----------------------- | ------------- | -------- | --------- |
| no speculation          | **91.7** tok/s | 79.3     | 27 628    |
| `ngram-mod` 8–16        | 90.7          | **89.7** | 27 644    |
| DSpark, `n-max 2`       | 71.6          | 76.5     | 30 117    |
| no speculation (repeat) | 91.2          | 78.2     | 27 628    |

DSpark's drafter reports 0.90 acceptance yet **still loses 20 t/s** — its
per-step cost exceeds what the accepted tokens buy back, which is consistent
with a 128-expert MoE where a draft batch re-reads all expert weights. It also
costs 2.4 GB. `ngram-mod` drafts from the token history, so it has no weights
and no buffers: it ties at cold start (within noise of the repeat pair) and is
13 % faster at depth, where prompts repeat structure. Hence the unit drops
`--model-draft` entirely.

An earlier pass appeared to show the opposite because it repeated the same
prompt three times inside one server; ngram-mod drafts from the context it has
already seen, so repeats inflate it. Cold, distinct prompts are the honest
measurement and are what the table above uses.

### Reasoning effort

The template default (0.9) versus the levels, same prompt, temperature 0:

| `reasoning_effort` | agent question | light coding |
| ------------------ | -------------- | ------------ |
| template default (0.9) | 1 068 tok / 12.1 s | 338 tok / 4.2 s |
| `medium`               | 435 tok / 4.9 s   | 328 tok / 3.4 s |
| `low` (unit default)   | **354 tok / 3.7 s** | 219 tok / 2.3 s |
| `minimal`              | 305 tok / 3.6 s   | 282 tok / 3.3 s |

`low` is not a quality sacrifice — on the agent question it produced the
better-targeted answer (it asked for the journal output instead of speculating),
for a third of the tokens and time. It is set as a **server default, not a cap**:
a client that sends `reasoning_effort` (or `chat_template_kwargs`) still
overrides it per request, verified up to `high`.

### Throughput summary

| Scenario                          | Result                    |
| --------------------------------- | ------------------------- |
| decode, short cold prompt         | ~91 tok/s                 |
| decode, at depth (~26K context)   | ~80–90 tok/s              |
| prefill, 26K prompt               | ~2 075 tok/s              |
| 2 concurrent requests (unified KV)| 407 tok in 3.4 s → 120 tok/s aggregate |
| time to first token, warm         | < 1 s                     |
| start (load 17.6 GB + 256K KV)    | ~4 s with weights in the page cache; minutes on the first cold read from disk |

## End-to-end checks (this unit, verbatim flags)

- text completion, `finish_reason: stop`, reasoning split into
  `message.reasoning_content` with the answer in `message.content`
- vision: 1600×1000 PNG sent as a data URL → `prompt_n` 1 030, correct
  description. `--image-max-tokens 4000` bounds what one image can consume.
- tool calling: `finish_reason: tool_calls` with
  `{"city":"Shanghai"}` — so agent frameworks can drive it directly
- `--parallel 2 --kv-unified`: two simultaneous requests, no slot errors
- `/metrics` 2 587 B, `/v1/models`, `/props` all healthy
- reasoning default verified live: 354 tokens, not 1 068

## Operations

```sh
systemctl --user daemon-reload
systemctl --user enable --now llama-server   # start + autostart on login
systemctl --user status llama-server          # logs via: journalctl --user -u llama-server -f
curl http://127.0.0.1:8080/v1/models          # health / model check
curl http://127.0.0.1:8080/metrics            # prometheus metrics (--metrics)
```

Checking for a newer binary: `llama-cpp-install.sh check` (read-only). To move,
edit `TAG` + `ASSET_SHA256`, run `reinstall`, then restart the unit.
Updating weights: `model-sync.sh update`, which re-reads the HF API and
re-downloads only files whose size or sha256 changed.

## Flags, and why each is there

| Flag | Reason |
| ---- | ------ |
| `--n-gpu-layers all` | 17.6 GB fits; nothing belongs on the CPU |
| `--ctx-size 262144` | largest context with usable headroom (see cliff table) |
| `--parallel 2` + `--kv-unified` | two agent sessions share one 256K pool instead of splitting it 128K each |
| `--flash-attn on` | required for quantised KV; sm_120 supports it |
| `--cache-type-k/v q8_0` | the fit decision: 1.6 GB cheaper than f16, −0.4 % decode |
| `--ubatch-size 1024` | +10 % prefill over 512; 2048 collapses prefill to 78 tok/s |
| `--spec-type ngram-mod` | free speculation; ties cold, +13 % at depth |
| `--cache-ram -1` | prompt cache unbounded in host RAM (78 GB available) |
| `--ctx-checkpoints 16` | cheap rewind points for long agent turns |
| `--metrics` | the table above is reproducible from `/metrics` |
| `--jinja` | the model's chat template needs it (tools, effort, thinking) |
| `--reasoning-effort low` | server default only; per-request override still works |
| `--image-max-tokens 4000` | bounds vision cost on a 32 GB card |
| `--temp/--top-p/--top-k/--min-p` | sampling defaults for OpenAI-compatible clients (clients override) |

No `--fit`: the defaults are already measured to fit, and `--fit` would silently
retune them per boot.

## Known limits

- **Do not copy this KV budget to a dense model.** q8_0 KV here is sized for a
  24-block MoE; a dense 27B needs far more KV per token.
- **q8_0 KV is a fit decision, not a speed decision.** At ≤128K, f16 is within
  noise — use f16 if you lower `--ctx-size`.
- **Headroom is 2.5 GB.** Raising `--ctx-size` past 256K, or adding another
  draft model, will cross the cliff and make prefill pathological rather than
  merely slower.
- **`--reasoning-effort low` is a default, not a cap.** Long reasoning tasks
  that need `high` must ask for it per request.
- **The first start after a reboot is slow** — the 17.6 GB of weights have to
  come off disk before anything answers, and the very first boot on a clean
  machine also downloads ~18 GB. Later starts are ~4 s while the page cache is
  warm.
