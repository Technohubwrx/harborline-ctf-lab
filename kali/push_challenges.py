#!/usr/bin/env python3
"""
Load the Harborline challenges, flags, hints and unlock order into CTFd.

Usage:
  python3 push_challenges.py --url http://127.0.0.1:8000 --token <admin_api_token> \
      --flags harborline_flags.json

Create the token in CTFd: Settings (top right, as admin) > Access Tokens.
Reads the harborline_flags.json copied from the Ubuntu VM.
Re-running deletes and recreates challenges with the same names.
"""
import argparse
import json
import sys
from pathlib import Path

import requests

HERE = Path(__file__).resolve().parent


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True, help="CTFd base URL, e.g. http://192.168.56.10")
    p.add_argument("--token", required=True, help="CTFd admin access token")
    p.add_argument("--flags", default="harborline_flags.json")
    p.add_argument("--challenges", default=str(HERE / "challenges.json"))
    args = p.parse_args()

    base = args.url.rstrip("/")
    s = requests.Session()
    s.headers.update({"Authorization": f"Token {args.token}",
                      "Content-Type": "application/json"})

    def call(method, path, **kw):
        r = s.request(method, base + path, timeout=15, **kw)
        if not r.ok:
            sys.exit(f"[!] {method} {path} failed: {r.status_code} {r.text[:300]}")
        return r.json()

    challenges = json.loads(Path(args.challenges).read_text())
    flags = json.loads(Path(args.flags).read_text())

    missing = [c["name"] for c in challenges if c["name"] not in flags]
    if missing:
        sys.exit(f"[!] No flag in flags.json for: {', '.join(missing)}")

    # Remove earlier copies so the script can be re-run after a rebuild
    existing = call("GET", "/api/v1/challenges?view=admin")["data"]
    names = {c["name"] for c in challenges}
    for c in existing:
        if c["name"] in names:
            call("DELETE", f"/api/v1/challenges/{c['id']}")
            print(f"[-] Removed old '{c['name']}'")

    ids = {}
    for c in challenges:
        data = call("POST", "/api/v1/challenges", json={
            "name": c["name"], "category": c["category"],
            "description": c["description"], "value": c["value"],
            "type": "standard", "state": "visible",
        })["data"]
        cid = data["id"]
        ids[c["name"]] = cid

        call("POST", "/api/v1/flags", json={
            "challenge_id": cid, "content": flags[c["name"]],
            "type": "static", "data": "",          # "" = case-sensitive
        })
        if c.get("hint"):
            call("POST", "/api/v1/hints", json={
                "challenge_id": cid, "content": c["hint"],
                "cost": c.get("hint_cost", 0),
            })
        print(f"[+] {c['name']} ({c['value']} pts) id={cid}")

    for c in challenges:
        if c["requires"]:
            prereqs = sorted(ids[n] for n in c["requires"])
            call("PATCH", f"/api/v1/challenges/{ids[c['name']]}", json={
                "requirements": {"prerequisites": prereqs, "anonymize": False}})
            print(f"[>] {c['name']} unlocks after: {', '.join(c['requires'])}")

    print(f"\nDone: {len(challenges)} challenges, "
          f"{sum(c['value'] for c in challenges)} points total.")


if __name__ == "__main__":
    main()
