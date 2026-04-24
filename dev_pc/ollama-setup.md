# Dev PC — Ollama setup

One-time setup on the Ubuntu side of the dev PC. Not automated — no
Ansible, no playbooks. Re-run these steps after any Ubuntu reinstall.

## Prerequisites

- Ubuntu 24.04 LTS
- Nvidia 5070 Ti with recent driver (`nvidia-smi` works)
- `192.168.1.173` as LAN IP (either DHCP reservation or static in netplan)

## Install Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama --version   # confirm install
```

## Bind Ollama to all interfaces

By default Ollama binds to `127.0.0.1:11434`. LiteLLM on the Pi needs to
reach it on the LAN, so we override to `0.0.0.0:11434`.

```bash
sudo systemctl edit ollama
```

Add in the editor:

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

Save. Then:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

Verify:

```bash
ss -tlnp | grep 11434
# should show *:11434 (LISTEN) on tcp/tcp6
```

## UFW — allow inbound from the Pi

If UFW is enabled:

```bash
sudo ufw allow from 192.168.1.252 to any port 11434 proto tcp \
  comment "Pi LiteLLM -> Ollama"
```

## Pull the Phase 3 models

```bash
# Primary coding model — Q4_K_M, ~9 GB. Fits comfortably on 5070 Ti 16GB.
# Using qwen 2.5 because Ollama-native qwen3-coder's smallest variant is
# 30B-MoE (~19 GB) which spills on 16 GB VRAM. Revisit when a smaller
# qwen3-coder tag lands (or move to a non-Ollama runtime).
ollama pull qwen2.5-coder:14b

# Local assistant slot — Q8_0 preferred for near-lossless quality.
# If qwen3.5:14b Q8_0 isn't in the Ollama library by default, pull the
# Unsloth GGUF instead:
#   ollama pull hf.co/unsloth/Qwen3.5-14B-GGUF:Q8_0
ollama pull qwen3.5:14b
```

Do **NOT** pull `qwen3.5:35b-a3b` — its 35B total weights exceed 16 GB
VRAM. Ollama falls back to CPU spill with a hard latency hit (~5 tok/s).
Skip unless you're deliberately experimenting with MoE on constrained VRAM.

## Smoke test from the Pi

```bash
ssh gooral@192.168.1.252 \
  'curl -sS http://192.168.1.173:11434/api/tags | head'
```

Expected: JSON listing `qwen2.5-coder:14b` and `qwen3.5:14b`.

## When booted to Windows

Do nothing. Ollama doesn't run; LiteLLM marks the endpoint down and
routes to DeepSeek / Claude / Proxmox Ollama depending on the alias.
When you boot back to Ubuntu, Ollama auto-starts via systemd and
LiteLLM's health check re-enables the endpoint within ~30 s.

## Rotation / updates

```bash
# Pull latest tags
ollama pull qwen2.5-coder:14b
ollama pull qwen3.5:14b

# Ollama itself
curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl restart ollama
```

No need to touch `systemctl edit` again — the override persists across
upgrades.
