# SentinelTrader VM — Provisioning Plan

Follow the same Ansible structure as `ollama_vm` / `smart_resume_vm`.

## VM Spec

| Parameter     | Value                  |
|---------------|------------------------|
| VM ID         | 104                    |
| Name          | `sentinel-trader`      |
| IP            | 192.168.1.202/24       |
| Gateway       | 192.168.1.1            |
| DNS           | 192.168.1.1            |
| Cores         | 4                      |
| RAM           | 6144 MB (6 GB)         |
| Disk          | 32 GB (app + SQLite)   |
| Template      | 9000 (Debian 12 cloud-init) |
| Storage       | local-lvm              |
| Node          | proxmox                |

## Services to install

1. **Python 3.12** — via deadsnakes PPA or pyenv
2. **sentinel-trader app** — clone repo, install as systemd service (use `sentinel-trader.service`)
3. **SQLite** — no server needed, file at `/opt/sentinel-trader/data/sentinel.db`
4. **Prometheus node_exporter** — port 9100 (standard node metrics)
5. **App metrics** — exposed by the app itself on port 9090 (`/metrics`)

## Systemd service

The repo contains `sentinel-trader.service`. Copy to `/etc/systemd/system/`, enable + start.
App reads config from `/opt/sentinel-trader/.env`.

## External dependencies (configure after provisioning)

- Ollama (Mistral 7B) is on **192.168.1.48:11434** — already running, reachable on LAN
- Broker API — credentials in `.env` (`XTB_USER_ID`, `XTB_PASSWORD`, `XTB_DEMO=true` to start)
- Anthropic API — `ANTHROPIC_API_KEY` in `.env`
- Telegram Bot — `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` in `.env`
- Finnhub, Alpha Vantage, Reddit — API keys in `.env`

## Ansible playbooks to create

```
sentinel_trader_vm/
├── ansible.cfg
├── group_vars/
│   └── all/
│       ├── vars.yml     # VM spec above + app config
│       └── vault.yml    # Passwords + API keys (ansible-vault)
├── inventory/
│   └── hosts.yml
├── Makefile
├── playbooks/
│   ├── create_vm.yml    # Proxmox clone + cloud-init (copy from ollama_vm)
│   ├── configure_vm.yml # Python, app install, systemd
│   ├── deploy_app.yml   # git pull + restart service
│   └── site.yml         # runs all in order
├── requirements.yml
└── templates/
    └── env.j2           # .env template from vault vars
```

## Notes

- No GPU needed (no local LLM — uses the shared Ollama VM at .48)
- 6 GB RAM is sufficient: Python app ~200 MB, SQLite in-process, no heavy services
- Grafana scrapes port 9090 — add a scrape target in the Grafana VM's Prometheus config
- Prometheus scrape config to add:
  ```yaml
  - job_name: 'sentinel-trader'
    scrape_interval: 30s
    static_configs:
      - targets: ['192.168.1.202:9090']
  ```
