# DECOMMISSIONED

The sentinel-trader VM (192.168.1.202) was removed from Proxmox around
2026-05 (its Prometheus scrape job was dropped 2026-05-12); the remaining
references were cleaned up in the 2026-09-06 decommission sweep
(`docs/sweep-2026-09-06.md`).

This directory is kept as provisioning code for a potential rebuild.
If rebuilding: re-add the Prometheus `sentinel-trader` job
(`network/prometheus/prometheus.yml`), a host-table row in
`~/.claude/CLAUDE.md`, and fresh credentials (the old ones were flagged
for revocation — see `nas/secrets-inventory.md` "Sentinel Trader").
