# network-pi (Ansible-managed)

Pi 4/5 host at `192.168.1.252` running the network-side Docker stack
(Caddy, Pi-hole, Authelia, Grafana, Prometheus, ntfy, Homarr, Uptime Kuma,
Loki/Promtail, Cloudflared, DIUN). Ansible owns OS-level config; the
Docker stack itself is deployed via `network/Makefile` from a checkout on
the Pi at `/opt/mati-lab`.

## Targets

```bash
make configure   # full run (idempotent)
make security    # ufw + ssh + fail2ban only
make docker      # docker engine + daemon.json + cron pruning
make power       # rpi-eeprom (boot/halt behaviour) + systemd watchdog
make check       # dry-run (--check --diff)
```

## Power resilience

`make power` configures three things:

1. **rpi-eeprom-config** (`/etc/rpi-eeprom/boot.conf`, applied via
   `rpi-eeprom-config --apply`):
   - `POWER_OFF_ON_HALT=0` — `shutdown -h` leaves the Pi ready to boot
     when power is reapplied. Default-on Pi 4/5 EEPROMs ship with `=1`,
     which can leave the Pi in a low-power state that ignores AC-restore
     until you yank and reseat the USB-C plug.
   - `BOOT_ORDER=0xf416` — NVMe → USB-MSD → SD → restart. A flaky NVMe
     no longer wedges the bootloader; the Pi falls back to SD if the
     NVMe drops off the PCIe bus mid-boot.
   - `WAKE_ON_GPIO=1` + `PSU_MAX_CURRENT=5000` — Pi 5 specifics for
     27W USB-C PD supplies. Ignored on Pi 4.
2. **systemd hardware watchdog** (`/etc/systemd/system.conf.d/watchdog.conf`):
   - `RuntimeWatchdogSec=30s` — if userspace stops pinging
     `/dev/watchdog`, the SoC self-reboots after 30s. Catches NVMe I/O
     stalls and kernel hangs that would otherwise leave a "lights on,
     network off" Pi.
   - `RebootWatchdogSec=2min` — if a shutdown sequence wedges
     (`systemd-fsck` waiting on input is the canonical case), force-reboot
     after 2 minutes instead of staying down.
3. **systemd-logind power-key handling**
   (`/etc/systemd/logind.conf.d/no-spurious-poweroff.conf`):
   - `HandlePowerKey=ignore` — software no longer reacts to short
     `KEY_POWER` events. The Pi 5 PMIC can inject these on brownouts, so
     the default `poweroff` handler turns a network appliance off any
     time the mains hiccups. See the 2026-05-22 postmortem below.
   - `HandlePowerKeyLongPress=poweroff` — held-button shutdown still
     works for a human at the box. Even without this, a real long press
     (>= ~5s) cuts power in PMIC hardware regardless of software config.

## Postmortem — 2026-05-22 outage

**Symptom:** Pi was unreachable from LAN/VPN for 1h12min. Lights on, no
network. Physical power-cycle recovered it cleanly.

**Timeline (from `journalctl -b -1`):**

| Time   | Event |
|--------|---|
| ~13:50 | NFS mount to NAS (`192.168.1.65:/mnt/bulk/backups`) starts timing out; Docker resolver also loses upstream DNS. Suggests Ethernet PHY flap from the same supply event that hit next. |
| 13:53:41 | `systemd-logind: Power key pressed short. Powering off...` — Pi 5 PMIC injected a `KEY_POWER` event into the input subsystem. Nobody was at the box. |
| 13:53:41 → 13:53:48 | Orderly shutdown ran; `mnt-nas-backups.mount` failed to unmount (NFS endpoint already gone) — non-fatal. `wtmp` got the `shutdown` record (which is why `last -x` shows a clean shutdown event). |
| 13:53:49 ish | Shutdown sequence **hung** before reaching final halt. sshd, the network stack, and Docker were already torn down; the kernel was still alive (green ACT LED was observed solid through to the manual power-cycle). PMIC never reached low-power state because the shutdown handoff to the SoC's halt path didn't complete. |
| 15:06 | Human power-cycle. Pi booted normally. |

**Cause:** the PMIC interpreted a supply transient as a power-button press.
The same signature is present in the journal on 2026-04-24 and 2026-04-26;
both were followed by a manual power-on within a minute (someone was
home to press the button back). On 2026-05-22 nobody was — so the
shutdown stuck.

**Fix landed in this PR (two independent layers):**
- `HandlePowerKey=ignore` so logind doesn't honour the spurious event in
  the first place. Stops the bad shutdown from being initiated.
- `RebootWatchdogSec=2min` is the second line of defence. The actual
  observed failure was a *stuck* shutdown (kernel alive, services dead,
  green ACT LED on) — exactly what `RebootWatchdogSec` recovers from:
  if shutdown takes more than 2 minutes, systemd's watchdog forces a
  reboot instead of leaving the Pi wedged.

Either fix alone would have made the May 2026 outage self-recover within
2 minutes. Both together also handle the next variant we haven't seen
yet.

### What this does NOT solve

### What this does NOT solve

- **Wake-on-LAN.** Pi 4 and Pi 5 Ethernet PHYs do not support magic-packet
  wake from full power-off. `WAKE_ON_GPIO=1` only wakes from the EEPROM's
  halt state (and only on Pi 5). The real remote-reboot answer is a smart
  plug on the USB-C feed.
- **SD-card / NVMe corruption.** The watchdog reboots a hung kernel, but
  if the boot media is unreadable nothing brings the Pi back without
  physical access. Keep a known-good SD card with the current image as a
  break-glass swap; see `nas/disaster-rebuild.md`.

## Files

- `playbooks/configure.yml` — full host bringup; tags split sections.
- `playbooks/backup.yml` — service backups to NAS NFS (see Phase 5).
- `templates/` — Jinja2 sources rendered into `/etc/...` on the Pi.
- `group_vars/all/vars.yml` — all tunables; vault file holds secrets.
