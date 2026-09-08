# Dev PC

Personal developer machine at `192.168.20.173` (Trusted VLAN 20 since the
2026-09-07 segmentation; was `192.168.1.173` on the flat LAN). **Not managed by Ansible** —
dual-boots Ubuntu (for dev + Ollama) and Windows (for gaming). Setup steps
are documented here for reproducibility after a reinstall; they are NOT
automated.

## Role in the homelab

- Ubuntu side runs Ollama on `:11434` (bound to all interfaces) serving
  larger models than the Proxmox VM can fit on its 8 GB 3070.
- LiteLLM on the NAS (`nas/litellm/`) uses this as the preferred
  endpoint for `coding` (gpt-oss:20b), one fallback tier of
  `agent-default`, and the `dev-ollama/*` wildcard (any model pulled
  here is routable by name). LiteLLM's health checks flap this
  endpoint up/down based on which OS is booted — that's expected.
- Dev PC is never a dependency of a 24/7 service. All homelab services
  must continue to work when the dev PC is off.

## Conventions

- No secrets live on this machine that aren't also on the dev user's
  regular workstation.
- SSH key from this machine to other homelab hosts uses
  `~/.ssh/id_ed25519`.
- No inbound connections except Ollama `:11434` from the NAS (LiteLLM,
  `192.168.1.65`). ufw is on with default-deny; since the VLAN move the
  NAS sits on a different subnet, so the allow rule must name it
  explicitly — see `ollama-setup.md`.

## Setup docs

- [`ollama-setup.md`](ollama-setup.md) — Ollama install + config + model
  pulls. Re-run after an Ubuntu reinstall.
- [`rtk-setup.md`](rtk-setup.md) — rtk (Rust Token Killer) install +
  per-agent wiring (Claude Code / opencode / codex) + safety config.
  Client-side shell-output token compression; orthogonal to the LiteLLM
  gateway. Re-run after an Ubuntu reinstall.
- [`litellm-clients.md`](litellm-clients.md) — routing the dev-PC CLI
  clients (opencode / codex / Claude Code) through the LiteLLM gateway.
  Client config lives in `~/.config/...`; this is the runbook.
