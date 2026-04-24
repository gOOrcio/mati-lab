# Dev PC

Personal developer machine at `192.168.1.173`. **Not managed by Ansible** —
dual-boots Ubuntu (for dev + Ollama) and Windows (for gaming). Setup steps
are documented here for reproducibility after a reinstall; they are NOT
automated.

## Role in the homelab

- Ubuntu side runs Ollama on `:11434` (bound to all interfaces) serving
  larger models than the Proxmox VM can fit on its 8 GB 3070.
- LiteLLM on the Pi (`network/litellm/`) uses this as the preferred
  endpoint for `coding` (qwen2.5-coder:14b) and one fallback tier of
  `agent-default` (qwen3.5:14b). LiteLLM's health checks flap this
  endpoint up/down based on which OS is booted — that's expected.
- Dev PC is never a dependency of a 24/7 service. All homelab services
  must continue to work when the dev PC is off.

## Conventions

- No secrets live on this machine that aren't also on the dev user's
  regular workstation.
- SSH key from this machine to other homelab hosts uses
  `~/.ssh/id_ed25519`.
- No inbound connections except Ollama `:11434` from the LAN.

## Setup docs

- [`ollama-setup.md`](ollama-setup.md) — Ollama install + config + model
  pulls. Re-run after an Ubuntu reinstall.
