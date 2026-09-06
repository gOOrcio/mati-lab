# Dev-PC model lab

Local playground for working with models directly — bespoke GGUFs,
quantization experiments, QLoRA fine-tuning — on the 5070 Ti (16 GB,
Blackwell/sm_120). Set up 2026-09-06. Everything lives in `~/model-lab/`
(NOT in this repo, NOT restic-backed — models/venvs are re-downloadable;
anything precious like LoRA adapters → copy into `~/model-lab/loras/`…
actually see "backups" below).

## Layout

```
~/model-lab/
  cuda-12.8/     user-space CUDA toolkit (system nvcc is 12.0 — too old for
                 sm_120; no root needed, system stays untouched)
  llama.cpp/     source build with CUDA (build/bin/llama-cli, llama-server,
                 llama-quantize, llama-gguf-split, convert_hf_to_gguf.py)
  venv/          python 3.12: torch cu128 + LLaMA-Factory + Unsloth
  models/        GGUFs (scratch)
  loras/         fine-tune outputs — the only dir worth keeping
  downloads/     installers, scratch
```

## Daily usage

```bash
# activate the training env
source ~/model-lab/venv/bin/activate

# run any HF GGUF directly, full knob access (interactive chat by default;
# add --single-turn for one-shot; the old -no-cnv flag is gone)
~/model-lab/llama.cpp/build/bin/llama-cli -m ~/model-lab/models/<x>.gguf \
  -ngl 99 -c 8192 --flash-attn on -p "..."

# big dense model on 16GB: aggressive quant + partial offload
#   -ngl <N> until VRAM full, rest on CPU; MoE models: --n-cpu-moe 20
# OpenAI-compatible server on :8080 (point IntelliJ/curl at it)
~/model-lab/llama.cpp/build/bin/llama-server -m <x>.gguf -ngl 99 --port 8080

# LLaMA-Factory web UI for fine-tuning (browser on :7860)
llamafactory-cli webui
```

## Fine-tune → serve conveyor

1. Train (LLaMA-Factory webui or Unsloth notebook) → LoRA adapter in
   `~/model-lab/loras/<name>/`.
2. Merge + convert:
   ```bash
   llamafactory-cli export --model_name_or_path <base> \
     --adapter_name_or_path ~/model-lab/loras/<name> \
     --export_dir ~/model-lab/loras/<name>-merged
   python ~/model-lab/llama.cpp/convert_hf_to_gguf.py \
     ~/model-lab/loras/<name>-merged --outfile ~/model-lab/models/<name>.f16.gguf
   ~/model-lab/llama.cpp/build/bin/llama-quantize \
     ~/model-lab/models/<name>.f16.gguf ~/model-lab/models/<name>.q4_k_m.gguf q4_k_m
   ```
3. Ship: `compute/dev_pc/model-lab/deploy-gguf.sh <gguf> <name>[:tag]`
   — `--local` first (test on the 16 GB card), then default target
   (ollama VM .48, **8 GB — keep shipped models ≤7B-Q4-ish**). The script
   prints the LiteLLM alias snippet for gateway exposure.

## VRAM cheat sheet (16 GB)

| Task | Fits? |
|---|---|
| Dense ≤14B inference, Q5/Q6, long ctx | comfortably |
| Dense 27B inference | Q3_XL/IQ4, short ctx, or partial offload |
| 30B-class MoE inference | yes, with `--n-cpu-moe ~20` |
| QLoRA fine-tune ≤14B (Unsloth) | yes (~8 GB for 8B) |
| QLoRA 20B+ | short seq-len only; rent a 48 GB spot GPU instead |
| Full fine-tune | ≤3B only |

## Gotchas

- **Always prefix builds with the lab CUDA**: `export PATH=$HOME/model-lab/cuda-12.8/bin:$PATH` —
  the system nvcc (12.0) silently produces non-sm_120 binaries.
- The dev-PC Ollama (gpt-oss:20b for IntelliJ) shares the 16 GB — stop it
  (`systemctl --user stop ollama` / close the app) before big training runs.
- llama.cpp built with `-DCMAKE_CUDA_ARCHITECTURES=120`; rebuild after
  `git pull` with the same cmake line (in notes below).
- Backups: `~/model-lab` is EXCLUDED from dev-pc restic (models are huge and
  re-downloadable). If a LoRA matters, copy it to `~/Projects/…` or add
  `model-lab/loras` to `compute/dev_pc/backup/restic-includes.txt`.

## Rebuild line

```bash
cd ~/model-lab/llama.cpp && git pull
export PATH=$HOME/model-lab/cuda-12.8/bin:$PATH
cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=120 \
  -DCMAKE_CUDA_COMPILER=$HOME/model-lab/cuda-12.8/bin/nvcc
cmake --build build --config Release -j 20
```
