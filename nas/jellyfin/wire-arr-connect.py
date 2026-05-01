#!/usr/bin/env python3
"""Wire Sonarr + Radarr → Jellyfin Connect (library refresh on import).

Usage:
    SONARR_KEY=... RADARR_KEY=... JELLYFIN_KEY=... \
        nas/jellyfin/wire-arr-connect.py

API keys come from environment so nothing secret lands in the repo:
- SONARR_KEY    — PM: homelab/sonarr/api-key (or read on-disk via
                  `ssh truenas_admin@nas 'sudo grep ApiKey /mnt/fast/databases/sonarr/config/config.xml'`)
- RADARR_KEY    — PM: homelab/radarr/api-key
- JELLYFIN_KEY  — PM: homelab/jellyfin/api-key-arr (mint via Jellyfin
                  Dashboard → API Keys → + Add → name `arr-import`)

Mints a "Jellyfin" notification entry on each *arr app, with triggers for
import/upgrade/delete events.

Idempotent: re-running with the same name fails with HTTP 400 ("Already
configured") on the second invocation; safe to ignore.
"""

import json
import os
import sys
import urllib.request

REQUIRED = ("SONARR_KEY", "RADARR_KEY", "JELLYFIN_KEY")
missing = [k for k in REQUIRED if not os.environ.get(k)]
if missing:
    print(f"missing env vars: {', '.join(missing)}\n\n{__doc__}", file=sys.stderr)
    sys.exit(2)

SONARR_KEY = os.environ["SONARR_KEY"]
RADARR_KEY = os.environ["RADARR_KEY"]
JELLYFIN_KEY = os.environ["JELLYFIN_KEY"]
JELLYFIN_HOST = os.environ.get("JELLYFIN_HOST", "192.168.1.65")
JELLYFIN_PORT = int(os.environ.get("JELLYFIN_PORT", "30013"))


def call(method, url, key, body=None):
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"X-Api-Key": key, "Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(req) as resp:
            t = resp.read().decode()
            return json.loads(t) if t else None
    except urllib.error.HTTPError as e:
        return {"_error": e.code, "_body": e.read().decode()[:500]}


def emby_notification(with_series_triggers):
    fields = [
        {"name": "host", "value": JELLYFIN_HOST},
        {"name": "port", "value": JELLYFIN_PORT},
        {"name": "useSsl", "value": False},
        {"name": "apiKey", "value": JELLYFIN_KEY},
        {"name": "notify", "value": True},
        {"name": "updateLibrary", "value": True},
    ]
    body = {
        "name": "Jellyfin",
        "onGrab": False,
        "onDownload": True,
        "onUpgrade": True,
        "onRename": True,
        "onHealthIssue": False,
        "onApplicationUpdate": False,
        "supportsOnGrab": False,
        "supportsOnDownload": True,
        "supportsOnUpgrade": True,
        "supportsOnRename": True,
        "supportsOnHealthIssue": False,
        "supportsOnApplicationUpdate": False,
        "includeHealthWarnings": False,
        "tags": [],
        "fields": fields,
        "implementationName": "Emby",
        "implementation": "MediaBrowser",
        "configContract": "MediaBrowserSettings",
    }
    if with_series_triggers:
        body["onSeriesDelete"] = True
        body["onEpisodeFileDelete"] = True
        body["onEpisodeFileDeleteForUpgrade"] = True
    else:
        body["onMovieDelete"] = True
        body["onMovieFileDelete"] = True
        body["onMovieFileDeleteForUpgrade"] = True
    return body


print("=== Sonarr ===")
r = call(
    "POST",
    "http://192.168.1.65:30026/api/v3/notification",
    SONARR_KEY,
    emby_notification(with_series_triggers=True),
)
print(json.dumps({k: r.get(k) for k in ("id", "name", "_error", "_body")}, indent=2))

print("=== Radarr ===")
r = call(
    "POST",
    "http://192.168.1.65:30027/api/v3/notification",
    RADARR_KEY,
    emby_notification(with_series_triggers=False),
)
print(json.dumps({k: r.get(k) for k in ("id", "name", "_error", "_body")}, indent=2))
