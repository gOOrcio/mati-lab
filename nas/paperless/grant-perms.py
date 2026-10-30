#!/usr/bin/env python3
"""Grant an ordinary Paperless user the permissions the workflow editor needs.

Break-glass/admin tool: the web UI is SSO-only, so the `admin` superuser can't
click through Settings → Users. This logs in to the REST API with admin basic
auth (password prompted, never echoed or stored) and adds the missing
permissions to USER, keeping the ones it already has.

Usage: nas/paperless/grant-perms.py [USER]          (default: gooral)
       nas/paperless/grant-perms.py USER --dry-run  (show what would be added)
"""
import argparse
import base64
import getpass
import json
import sys
import urllib.error
import urllib.request

BASE = "https://paperless.mati-lab.online/api"

# Workflow editor loads custom fields and users/groups, and saving a workflow
# creates trigger/action sub-objects, each with its own model permission.
MODELS = (
    "customfield",
    "workflow",
    "workflowtrigger",
    "workflowaction",
    "workflowactionemail",
    "workflowactionwebhook",
)
WANT = {f"{a}_{m}" for a in ("view", "add", "change", "delete") for m in MODELS}
WANT |= {"view_user", "view_group"}


def call(auth, path, data=None, method="GET"):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(data).encode() if data is not None else None,
        method=method,
        headers={
            "Authorization": auth,
            "Content-Type": "application/json",
            "Accept": "application/json; version=9",
        },
    )
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} failed: HTTP {e.code} {e.read().decode()[:400]}")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("user", nargs="?", default="gooral")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    pw = getpass.getpass("Paperless admin password: ")
    auth = "Basic " + base64.b64encode(f"admin:{pw}".encode()).decode()
    del pw

    users = call(auth, f"/users/?username__iexact={args.user}")["results"]
    if not users:
        sys.exit(f"user {args.user!r} not found")
    user = users[0]
    if user.get("is_superuser"):
        sys.exit(f"{args.user} is a superuser; refusing (design: ordinary users only)")
    have = set(user.get("user_permissions", []))
    missing = sorted(WANT - have)
    if not missing:
        print(f"{args.user}: nothing to add")
        return
    print(f"{args.user}: adding {missing}")
    if args.dry_run:
        return
    call(auth, f"/users/{user['id']}/", {"user_permissions": sorted(have | WANT)}, "PATCH")
    print("done")


if __name__ == "__main__":
    main()
