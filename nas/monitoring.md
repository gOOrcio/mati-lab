# NAS monitoring — Prometheus + Grafana via Netdata-Graphite bridge

## Pipeline

```
TrueNAS Netdata → Carbon (tcp/2003) → graphite-exporter (Pi) → /metrics :9108 → Prometheus → Grafana
```

## Why this architecture

TrueNAS Scale 25.10 Goldeye has no native Prometheus endpoint. The catalog
doesn't ship `node-exporter` or `cadvisor`, and "Custom App" installs choke
on host-network requirements. What TrueNAS *does* ship is a built-in
**Netdata Graphite exporter** under **System Settings → Advanced →
Reporting Exporters**. We point that at a `graphite-exporter` container on
the Pi, which translates Carbon line protocol into Prometheus format.

Benefit: zero NAS-side plumbing beyond one UI toggle. TrueNAS keeps owning
its metric collection; we just redirect the output.

## TrueNAS-side configuration

System Settings → Advanced Settings → Reporting Exporters → Add:

| Field | Value |
|---|---|
| Type | `GRAPHITE` |
| Enable | ✓ |
| Destination IP | `192.168.1.252` (the Pi) |
| Destination Port | `2003` |
| Prefix | `netdata` |
| Namespace | `truenas` |
| Send Names Instead Of IDs | ✓ |

This emits Carbon-format metrics like:

```
netdata.truenas.truenas.arcstats.size.size <value> <timestamp>
netdata.truenas.system.load.load1 <value> <timestamp>
netdata.truenas.cpu.usage.cpu.cpu0 <value> <timestamp>
```

## Pi-side stack

`network/graphite-exporter/`:
- `docker-compose.yml` — `prom/graphite-exporter:v0.16.0`, listens on
  `:2003/tcp` (Carbon) and `:9108/tcp` (Prometheus `/metrics`).
- `mapping.yml` — translates dotted Graphite names into Prometheus metrics
  with a `host` label. Currently coarse (preserves chart names in the
  metric identifier); refine later if label explosion becomes a problem.

`network/prometheus/prometheus.yml`:

```yaml
- job_name: graphite-exporter
  scrape_interval: 30s
  static_configs:
    - targets: [ 'graphite-exporter:9108' ]
```

## What metrics are available

Netdata on TrueNAS 25.10 emits a limited subset (25.04+ dropped many default
charts and migrated to custom Python scripts). Useful families we get:

| Prefix | What |
|---|---|
| `netdata_truenas_arcstats_*` | ZFS ARC (hit rate, size, L2ARC) |
| `netdata_truenas_cpu_usage_cpu_cpu{0..N}` | Per-core CPU usage |
| `netdata_truenas_meminfo_total_total` / `_available_available` | RAM totals |
| `netdata_truenas_disk_stats_*_reads` / `_writes` | Per-disk I/O (by serial) |
| `netdata_system_load_load{1,5,15}` | Load average |
| `netdata_system_uptime_uptime` | Uptime |
| `netdata_system_active_processes_active` | Process count |
| `netdata_system_net_received` / `_sent` | Total NAS NIC traffic |
| `netdata_cputemp_temperatures_cpu{0..7}` | Per-core CPU temperatures |
| `netdata_cgroup_<id>_cpu_user` / `_mem_usage_ram` / `_io_{read,write}` | Per-container metrics (Jellyfin, qBittorrent, cloudflared) |

All labelled with `host="truenas"` so multiple TrueNAS hosts can share
the job later.

## Known absent metrics

- No top-level `netdata_cpu_cpu_user` / per-CPU "user/system/idle" breakdown
  (TrueNAS 25.10 dropped the `system.cpu` chart by default).
- No top-level `mem.available` / `mem.used` (`meminfo` has totals only).
- No ZFS pool-level stats (arcstats only — ARC hits/misses/size, not
  per-pool IO). If you need pool-level, add a separate `zfs_exporter`
  scrape on the NAS later.

The community [Supporterino/truenas-graphite-to-prometheus][supporterino]
project has a `netdata.conf` override that restores pre-25.04 metrics —
consider in Phase 8 if the default subset proves insufficient. Fragile
because TrueNAS manages Netdata itself and upgrades may wipe the override.

## Grafana dashboard

UID `truenas-nas-overview` at `https://grafana.mati-lab.online/d/truenas-nas-overview/`.
Managed via the Grafana API (existing workflow preference). Not
file-provisioned. Nightly export via `make save-grafana` will snapshot it
to `provisioning/dashboards/` for git backup.

Panels (initial): ARC size, memory available, uptime, active processes,
per-core CPU, load average, CPU temps, network throughput, top-5 containers
by CPU, ARC hits vs misses. Expand as usage patterns emerge.

## Smoke-test commands

```bash
# Bridge receiving Carbon
ssh gooral@192.168.1.252 'docker exec graphite-exporter wget -qO- http://localhost:9108/metrics | grep -c "^netdata_"'

# Prometheus scraping UP
ssh gooral@192.168.1.252 'docker exec prometheus wget -qO- http://localhost:9090/api/v1/targets | grep -o "\"job\":\"graphite-exporter\"[^}]*\"health\":\"up\""'

# PromQL sanity query
ssh gooral@192.168.1.252 'docker exec prometheus wget -qO- "http://localhost:9090/api/v1/query?query=netdata_truenas_arcstats_size_size"'
```

[supporterino]: https://github.com/Supporterino/truenas-graphite-to-prometheus
