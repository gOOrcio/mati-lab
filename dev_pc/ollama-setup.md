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
sudo ufw allow from 192.168.1.252 to any port 11434 proto tcp comment "Pi LiteLLM -> Ollama"
```

## Pull the Phase 3 models

```bash
# Primary coding model — Q4_K_M, ~9 GB. Fits comfortably on 5070 Ti 16GB.
# Using qwen 2.5 because Ollama-native qwen3-coder's smallest variant is
# 30B-MoE (~19 GB) which spills on 16 GB VRAM. Revisit when a smaller
# qwen3-coder tag lands (or move to a non-Ollama runtime).
ollama pull qwen2.5-coder:14b

# Local assistant slot — last-resort fallback for Hermes if DeepSeek +
# Claude are both down. qwen3.5:14b doesn't exist in Ollama's library;
# qwen2.5:14b-instruct is the equivalent size-class dense model that does.
ollama pull qwen2.5:14b-instruct
```

Do **NOT** pull `qwen3.5:35b-a3b` or other 20GB+ variants — they exceed
16 GB VRAM. Ollama falls back to CPU spill with a hard latency hit
(~5 tok/s). Skip unless you're deliberately experimenting.

## Smoke test from the Pi

```bash
ssh gooral@192.168.1.252 \
  'curl -sS http://192.168.1.173:11434/api/tags | head'
```

Expected: JSON listing `qwen2.5-coder:14b` and `qwen2.5:14b-instruct`.

## When booted to Windows

Do nothing. Ollama doesn't run; LiteLLM marks the endpoint down and
routes to DeepSeek / Claude / Proxmox Ollama depending on the alias.
When you boot back to Ubuntu, Ollama auto-starts via systemd and
LiteLLM's health check re-enables the endpoint within ~30 s.

## Rotation / updates

```bash
# Pull latest tags
ollama pull qwen2.5-coder:14b
ollama pull qwen2.5:14b-instruct

# Ollama itself
curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl restart ollama
```

No need to touch `systemctl edit` again — the override persists across
upgrades.
