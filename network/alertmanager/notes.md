# Alertmanager (Pi)

Phase 8 add-on to the existing Prometheus + Grafana stack. Reads firing
alerts from Prometheus rules in `network/prometheus/rules/*.yml`, routes
them to a single ntfy webhook receiver (the `homelab-alerts` topic on
`http://ntfy:80/` — same destination as Uptime Kuma + the
grafana-ntfy-bridge).

## Endpoints

- **UI behind Authelia 2FA:** `https://alertmanager.mati-lab.online`
- **Inside `pihole-net`:** `alertmanager:9093` (Prometheus + grafana-ntfy-bridge talk to it)
- **No native auth** — Caddy forward_auth is the only gate. Don't bypass.

## What it actually alerts on

Today (Phase 8 install):

| Rule group | Alert | Condition | Severity |
|---|---|---|---|
| `scrape-health` | `ScrapeTargetDown` | `up == 0` for >5m | warning |
| `scrape-health` | `ScrapeTargetMissingForLong` | `up == 0` for >1h | critical |
| `litellm` | `LiteLLMHighErrorRate` | error/total > 5% over 10m | warning |
| `litellm` | `LiteLLMKeyBudgetNearExhausted` | remaining_api_key_budget_metric < $1 | warning |

**ZFS pool capacity / SMART / pool DEGRADED is NOT here** — see
`nas/backup-jobs/zfs-health-cron.sh`. The Graphite-bridge from Netdata
doesn't expose those in a useful PromQL shape; daily cron + ntfy is
simpler than chasing a proper exporter today.

## Routing

Single route to a single receiver (`ntfy`). Group by `[alertname, host, pool]`,
group_wait 10s, group_interval 5m, repeat_interval 12h. Inhibit rule
suppresses warning-pool-full when critical-pool-full fires for the same
(pool, host).

When more receivers / severity-routes / time-windows accumulate, split
the route tree and split rule files by domain.

## Adding a new rule

1. Create or edit `network/prometheus/rules/<group>.yml` in this repo.
2. Verify metric names exist via the Prometheus UI:
   `https://prometheus.mati-lab.online/graph` → query → confirm series.
3. `cd network && make deploy-prometheus` (Prometheus reads rule files
   from the bind mount on every start; SIGHUP via `kill -HUP` would also
   work).
4. Confirm in Alertmanager UI under Status → Config that the rule shows
   up.

## Adding a new receiver

1. Edit `network/alertmanager/alertmanager.yml`.
2. `cd network && make deploy-alertmanager`.
3. Verify in `https://alertmanager.mati-lab.online/#/status` that the
   new config is loaded (Alertmanager hot-reloads on SIGHUP; the deploy
   recreates the container so config is picked up either way).

## Silencing a known-noise alert

Use the UI: `https://alertmanager.mati-lab.online/#/silences/new`. Set
the matcher (e.g. `alertname=ScrapeTargetDown, instance=192.168.1.173:3001`)
and a comment explaining WHY. Silences expire — set the duration to
match the underlying issue (e.g. "until restorate-dev VM is back up").

For permanently-down targets, prefer dropping them from
`network/prometheus/prometheus.yml` over silencing forever. Silences
without expiry quietly accumulate.

## Lessons (to populate as we hit them)

- (Reserved.)
