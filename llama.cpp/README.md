# llama-server — Qwen3.8-27B IQ4_XS (2x RTX 2080 Ti, 22GB)

Local OpenAI-compatible API server for Qwen3.8-27B, quantized with
unsloth Dynamic V3.0 (IQ4_XS, 15.7 GB), running on two RTX 2080 Ti via
llama.cpp CUDA. All agents/tools point at `http://127.0.0.1:8080/v1`.

## Layout

| Path | What |
|---|---|
| `~/.config/systemd/user/llama-server.service` | systemd user unit |
| `~/.local/lib/qwen38-model-sync.sh` | model ensure/verify/update script |
| `~/.cache/huggingface/hub/models--unsloth--Qwen3.8-27B-GGUF/` | model cache (huggingface default dir, `hf`/`hfd` compatible) |

## Usage

```bash
systemctl --user daemon-reload
systemctl --user enable --now llama-server   # start + autostart on login
systemctl --user status llama-server          # logs via: journalctl --user -u llama-server -f
curl http://127.0.0.1:8080/v1/models          # health / model check
```

Point any OpenAI-compatible client at `http://127.0.0.1:8080/v1`,
model id as shown by `/v1/models` (typically the GGUF filename).

## Model management

- **Auto-download**: on every start, `ExecStartPre` runs the sync script;
  if the GGUF is missing/incomplete it downloads via hfd (aria2,
  hf-mirror mirror, resumable) and verifies sha256.
- **Verify**: `~/.local/lib/qwen38-model-sync.sh verify`
- **Force update** (e.g. upstream republished the quant):
  `~/.local/lib/qwen38-model-sync.sh update && systemctl --user restart llama-server`

## Final unit (deployed 2026-08-20)

```
--parallel 2 --ctx-size 32768          # 2 slots × 16K each
--n-gpu-layers auto --split-mode layer --tensor-split 1,1
--cache-type-k q8_0 --cache-type-v q8_0
--spec-type draft-mtp --spec-draft-n-max 4 --spec-draft-p-min 0.75   # MTP ON
--reasoning-preserve --jinja
```

- **MTP speculative decoding is ON.** The unsloth GGUF carries the `nextn`
  head. Community recipe (github.com/sudoingX/qwen38-mtp) + local tuning:
  bandwidth-starved cards need `--spec-draft-p-min 0.60-0.75` to make deep
  drafting cheap. Measured A/B on this box (same config, 400-token gen):
  **26.9 → 43.5 t/s (+62%)**. Short generations (<200 tok) gain little or
  pay overhead; full benefit shows at 400+ tokens — good for agent workloads.
- **Why not 8 slots / 64K**: 64K total ctx + MTP rs-cache needs ~3.1 GB/card
  over the 22 GB budget (OOM). 2×16K fits at ~9.7 GB/card with 1.5 GB headroom.
- **`--split-mode tensor` — tested WITH NCCL: measured slower, keep layer.**
  Rebuilt llama.cpp-cuda with `-DGGML_CUDA_NCCL=ON` (PKGBUILD: makedepends
  nccl + cmake flag; sm_75 only). This pair HAS NVLink (2 x 25.78 GB/s,
  `nvidia-smi topo -m` = NV2). Tensor split then loads fine (no more hang)
  but is SLOWER than layer on 2x16K + MTP: 37.8 vs 41.7-43.5 tok/s (-10~13%),
  with VRAM pinned at 10.9 GB/card (383 MB headroom). On Turing the per-layer
  cross-GPU AllReduce sync cost outweighs the compute split; layer split only
  ships activations and wins. NCCL build stays in the AUR package (harmless,
  makes tensor available if hardware ever changes).
- **Why not MTP-only changes first try**: initial test with `--draft-max`
  (removed flag) and no p-min showed +1%; the p-min gate is the key.
- KV: `q8_0` halves footprint; only 16/64 layers use KV in this model.
- `--reasoning-preserve` returns Qwen3.8's ` thinking` as `reasoning_content`
  for agents. Some clients pass `enable_thinking: false` but llama.cpp's
  OpenAI layer does not forward it — set `max_tokens` generously.
- CUDA libs: unit sets `LD_LIBRARY_PATH=/opt/cuda/lib64`; `sudo ldconfig` was
  also run so interactive shells resolve them too.

## Community background (Qwen3.8-27B + llama.cpp)

- llama.cpp supports MTP spec decode via PR #22673; activate with
  `--spec-type draft-mtp` plus `--spec-draft-n-max` (card-dependent; 2-4 here,
  4 measured best on our tier) and `--spec-draft-p-min` on slow cards.
- Multi-GPU: fix split mode before tuning; `--split-mode tensor` beat layer
  by +68% on 5060 Ti pairs (3× on the whole), but needs NCCL+P2P we lack.
- MTP is single-stream: advantage gone by `--parallel 4`; measure at
  `--parallel 1`. 2-4 slots is the workable band for MTP on this hardware.
- Comparable old-card data point: 2× Tesla P40 (tensor split, no P2P) got
  +77% (13.2 → 23.4) with n-max 4 + p-min 0.75 — same tunning rules.

## WSL2 notes

- The user unit stops when WSL shuts down. To auto-start on WSL boot, add to
  `%UserProfile%\.wslconfig` (Windows side):
  `[boot] command="systemctl --user start llama-server"` (requires
  `systemd=true` in `/etc/wsl.conf`; this machine also has a custom `wslarc`
  hook there — keep it when editing).
- Driver: host 610.88 / CUDA UMD 13.3 pairs with CUDA 13.3 llama.cpp build.
  After a driver upgrade, cold-boot WSL (`wsl --shutdown`); if `nvidia-smi`
  says "Driver Not Loaded" and a fresh distro works, check for per-distro
  boot hooks (`wslarc`) interfering with dxg init.

## Measured performance (2026-08-20)

| Scenario | t/s |
|---|---|
| 2 slots × 16K, no MTP (A/B control) | 26.9 |
| 2 slots × 16K, MTP n4 p0.75 (400+ tok) | **43.5** (+62%) |
| short generations (<200 tok) | 24-33 (MTP overhead) |
| 2 concurrent requests | both OK, 15-34 t/s shared |
| prefill | 11-28 tok/s (Turing FP16)