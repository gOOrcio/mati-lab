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

## codex ✅ configured (opt-in profile)

`~/.codex/config.toml` defines a `litellm` provider + a `gateway` profile.
Kept **opt-in** rather than default because codex's own ChatGPT/Codex
subscription login is otherwise intact — making the gateway the default
would bill DeepSeek/local/Claude-API instead of that sub. Use on demand:

```toml
[model_providers.litellm]
name = "LiteLLM homelab gateway"
base_url = "http://192.168.1.65:4000/v1"
env_key = "LITELLM_API_KEY"
wire_api = "responses"     # current codex REQUIRES "responses" (rejects "chat")

[profiles.gateway]
model = "agent-default"
model_provider = "litellm"
```

```bash
export LITELLM_API_KEY=<dev-pc-tools or claude-code key>
codex exec -p gateway "reply: gateway ok"    # verified: returns "gateway ok"
```

To make the gateway codex's **default** (abandoning the ChatGPT sub for
codex), add top-level `model_provider = "litellm"` + `model = "..."`.
**`wire_api = "responses"` is mandatory** — current codex rejects `"chat"`
at startup (`wire_api = "chat" is no longer supported`). LiteLLM serves the
Responses API at `/v1/responses` (verified), so codex works against it with
`"responses"`. (An earlier draft used `"chat"`, which newer codex refuses.)

## Claude Code 🟡 staged (launcher ready; needs a key + Step #2 forwarding)

CC keeps its own **subscription OAuth** login (now **Max**); the gateway
authenticates it on `x-litellm-api-key` and forwards the OAuth upstream so
the Max sub is billed. An **isolated launcher `~/.local/bin/claude-gw`** is
in place — run `claude-gw` to use the gateway; a plain `claude` is
untouched. It refuses to start without a key, so it can't misbehave:

```bash
export CLAUDE_CODE_GW_KEY=<a LiteLLM 'claude-code' virtual key>   # add to ~/.zshrc
claude-gw            # launches Claude Code pointed at the gateway
```

Remaining to fully cut over (all need the master key):
1. **Issue the `claude-code` virtual key** (scoped to `claude-*`) — `nas/litellm/notes.md` "Virtual keys".
2. **Deploy the Step #2 scoped OAuth-forwarding config** (`nas/litellm/notes.md` "Step #2") so the **Max subscription** is billed rather than the API key. Before this, `claude-gw` still works but bills the Anthropic API key (the `claude-*` aliases carry `ANTHROPIC_API_KEY`).
3. **Validate** with a throwaway `claude-gw` in a scratch dir — check `/spend/logs` to confirm the turn billed the subscription (forwarded OAuth), not the API key.

Design: `docs/superpowers/specs/2026-07-16-litellm-cc-subscription-cutover-design.md`.
