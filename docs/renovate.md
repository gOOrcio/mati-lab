# Renovate (centralised dependency updates)

Self-hosted [Renovate](https://docs.renovatebot.com/) runs as a scheduled Gitea
Actions workflow (`.gitea/workflows/renovate.yml`) and **autodiscovers every repo
the bot token can access**, opening dependency-update PRs. It replaces GitHub
Dependabot, which was removed when CI moved from GitHub Actions to Gitea.

- **Schedule:** weekly, Monday 06:00 UTC (plus manual `workflow_dispatch`, with
  `logLevel` and `dryRun` inputs).
- **Runner:** the gitea-runner VM, inside the `renovate/renovate` container.
- **Onboarding:** each discovered repo first gets a "Configure Renovate" PR; merge
  it (or add a `renovate.json`) to activate that repo. Per-repo behaviour is then
  controlled by that repo's config; the global defaults are `config:recommended`.

## One-time setup — the bot token (manual; never commit the value)

1. Create a Gitea Personal Access Token, ideally for a dedicated `renovate` bot
   account (or your own account), with **repository read & write** scope.
   Gitea → Settings → Applications → Generate New Token.
2. Add it as the Actions secret `RENOVATE_TOKEN` on the `gooral/mati-lab` repo.
   **Preferred — Gitea UI** (keeps the value out of shell history):
   repo → Settings → Actions → Secrets → Add Secret → name `RENOVATE_TOKEN`.

   Or via `tea` (the value becomes a CLI argument — clear it from your shell
   history afterwards):

   ```sh
   tea actions secrets create RENOVATE_TOKEN '<token>' \
     --repo gooral/mati-lab --login gitea.mati-lab.online
   ```
3. (Optional) Add `RENOVATE_GITHUB_COM_TOKEN` — a **read-only** github.com PAT —
   to avoid changelog/release-note rate limits.

Until `RENOVATE_TOKEN` exists, the scheduled run no-ops with an auth error.

## Verify

```sh
# Dry run first — logs what it would do, opens no PRs:
tea actions workflows dispatch renovate.yml \
  --repo gooral/mati-lab --login gitea.mati-lab.online \
  --ref main -i dryRun=full -i logLevel=debug
```

Then dispatch without `dryRun` (or wait for the weekly cron) to let it open the
onboarding PRs.
