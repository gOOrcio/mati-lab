# Dev PC — routing CLI clients through the LiteLLM gateway

Campaign #2 (client cutover). Makes the dev-PC LLM clients hit the LiteLLM
gateway at `http://192.168.1.65:4000` instead of talking to providers
directly — for unified routing, spend visibility, budgets, prompt-cache
injection, and local-model fallback.

Client config lives outside this repo (`~/.config/...`), per the dev-PC
docs-only convention. This file is the reproducibility runbook.

## Virtual key

All non-Claude clients authenticate to the gateway with a LiteLLM
**virtual key** (never the master key). The existing `dev-pc-tools` key
(PM `homelab/litellm/dev-pc-tools`) grants `agent-default`, `agent-smart`,
`coding`, `embeddings`. Export it for ad-hoc tooling:

```bash
export LITELLM_API_KEY=<dev-pc-tools virtual key from PM>   # add to ~/.zshrc
```

To also reach the `claude-*` aliases through the gateway, issue a
`claude-code` key (needs the master key — see `nas/litellm/notes.md`).

## opencode ✅ configured

`~/.config/opencode/opencode.json` defines a custom OpenAI-compatible
provider `litellm` pointing at the gateway; the API key is an env-var
reference (no secret in the file):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "litellm/agent-default",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM (homelab gateway)",
      "options": {
        "baseURL": "http://192.168.1.65:4000/v1",
        "apiKey": "{env:LITELLM_API_KEY}"
      },
      "models": {
        "agent-default": { "name": "agent-default (DeepSeek → Claude → gpt-oss local)" },
        "agent-smart":   { "name": "agent-smart (Claude Sonnet)" },
        "coding":        { "name": "coding (gpt-oss:20b local → DeepSeek → qwen3.5:9b)" }
      }
    }
  }
}
```

Verify (no key needed): `opencode models litellm` → lists the three
`litellm/*` models. Activate + smoke-test (needs the key exported):

```bash
export LITELLM_API_KEY=<dev-pc-tools key>
opencode run -m litellm/agent-default "reply: gateway ok"
```

Default model is `agent-default` (DeepSeek — a validated path). Switch to
`litellm/coding` (local gpt-oss:20b first) once the reasoning-model
content-through-gateway check passes.

## codex ⏳ pending

Codex reads `~/.codex/config.toml`. Add a `model_providers` entry for the
gateway (OpenAI-compatible, `base_url = "http://192.168.1.65:4000/v1"`,
env-key), then select a gateway model. To document when wired.

## Claude Code ⏳ pending (campaign #2 subscription forwarding)

CC keeps its own **subscription OAuth** login (now **Max**) and points at
the gateway, which forwards the OAuth upstream:

```bash
export ANTHROPIC_BASE_URL=http://192.168.1.65:4000
export ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer <claude-code key>"
```

Apply via an isolated wrapper (`~/.local/bin/claude-gw`), **not** globally —
the running session stays on direct auth until deliberately cut over.
Blocked on: server-side scoped OAuth-forwarding config (documented in
`nas/litellm/notes.md` "Step #2") + master-key validation + a throwaway-CC
end-to-end test. See `docs/superpowers/specs/2026-07-16-litellm-cc-subscription-cutover-design.md`.
