#!/usr/bin/env python3
"""Relay Archive: keeps a plain-text log of every iMessage conversation.

Runs on your NAS (in Docker). Every few minutes it asks your Mac's BlueBubbles
Server for new messages and appends them to one folder per conversation:

  /data/<Chat name> [abc123]/2026-10.txt      readable log, one file per month
  /data/<Chat name> [abc123]/messages.jsonl   same messages as data, for searching

Only text is saved (attachments appear as "[attachment: name]").
Uses nothing but Python's standard library.
"""
import hashlib
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime

URL = os.environ.get("BB_URL", "").rstrip("/")
PASSWORD = os.environ.get("BB_PASSWORD", "")
OUT = os.environ.get("OUT", "/data")
INTERVAL = int(os.environ.get("INTERVAL", "300"))
ONCE = os.environ.get("ONCE") == "1"
PAGE = 500
TAPBACKS = set(range(2000, 2006)) | set(range(3000, 3006))


def log(*a):
    print(datetime.now().strftime("%Y-%m-%d %H:%M:%S"), *a, flush=True)


def call(method, path, body=None, params=None):
    q = {"guid": PASSWORD}
    q.update(params or {})
    url = f"{URL}/api/v1{path}?{urllib.parse.urlencode(q)}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json", "User-Agent": "relay-archive"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode("utf-8"))["data"]


def digits(s):
    d = re.sub(r"\D", "", s or "")
    return d[-10:] if len(d) >= 10 else (s or "").lower()


def contact_names():
    names = {}
    try:
        for c in call("GET", "/contact"):
            n = c.get("displayName") or " ".join(x for x in [c.get("firstName"), c.get("lastName")] if x)
            if not n:
                continue
            for k in ("phoneNumbers", "emails"):
                for e in c.get(k) or []:
                    a = e.get("address") if isinstance(e, dict) else e
                    if a:
                        names[digits(a)] = n
    except Exception as e:  # names are a nicety
        log("contacts unavailable:", e)
    return names


def chat_titles(names):
    titles = {}
    off = 0
    while True:
        page = call("POST", "/chat/query", {"limit": PAGE, "offset": off, "with": ["participants"]})
        for c in page:
            t = c.get("displayName") or ", ".join(names.get(digits(h.get("address")), h.get("address", "?")) for h in c.get("participants") or []) or "Unknown"
            titles[c["guid"]] = t
        if len(page) < PAGE:
            return titles
        off += PAGE


def safe(s):
    s = re.sub(r'[\\/:*?"<>|\r\n\t]', " ", s).strip(" .")
    return (s or "Chat")[:60]


def folder(guid, title):
    short = hashlib.sha1(guid.encode()).hexdigest()[:6]
    p = os.path.join(OUT, f"{safe(title)} [{short}]")
    os.makedirs(p, exist_ok=True)
    return p


def who(m, names):
    if m.get("isFromMe"):
        return "Me"
    a = (m.get("handle") or {}).get("address", "")
    return names.get(digits(a), a or "?")


def line(m, names):
    ts = datetime.fromtimestamp(m["dateCreated"] / 1000)
    text = (m.get("text") or "").replace("￼", "").strip()
    atts = [a.get("transferName") or "file" for a in m.get("attachments") or []]
    parts = ([text] if text else []) + [f"[attachment: {n}]" for n in atts]
    body = " ".join(parts).replace("\n", "\n    ")
    return ts, f"{ts.strftime('%Y-%m-%d %H:%M')}  {who(m, names)}: {body}\n"


def load_state():
    try:
        with open(os.path.join(OUT, ".state.json")) as f:
            return json.load(f)
    except Exception:
        return {"last_ts": 0, "seen": []}


def save_state(s):
    tmp = os.path.join(OUT, ".state.json.tmp")
    with open(tmp, "w") as f:
        json.dump(s, f)
    os.replace(tmp, os.path.join(OUT, ".state.json"))


def run_once():
    state = load_state()
    names = contact_names()
    titles = chat_titles(names)
    seen = set(state["seen"])
    last = state["last_ts"]
    total = 0
    off = 0
    while True:
        page = call("POST", "/message/query", {
            "limit": PAGE, "offset": off, "sort": "ASC", "after": max(last - 1, 0), "with": ["chat", "handle", "attachment"],
        })
        for m in page:
            if m["guid"] in seen or not m.get("dateCreated"):
                continue
            chats = m.get("chats") or []
            if not chats:
                continue
            g = chats[0]["guid"]
            title = titles.get(g) or chats[0].get("displayName") or chats[0].get("chatIdentifier") or "Unknown"
            d = folder(g, title)
            with open(os.path.join(d, "messages.jsonl"), "a", encoding="utf-8") as f:
                f.write(json.dumps({"guid": m["guid"], "time": m["dateCreated"], "from": who(m, names), "fromMe": bool(m.get("isFromMe")),
                                    "text": m.get("text"), "attachments": [a.get("transferName") for a in m.get("attachments") or []],
                                    "tapback": m.get("associatedMessageType")}, ensure_ascii=False) + "\n")
            if m.get("associatedMessageType") not in TAPBACKS and (m.get("itemType") in (None, 0)):
                ts, txt = line(m, names)
                if txt.strip().endswith(":"):
                    pass
                else:
                    with open(os.path.join(d, ts.strftime("%Y-%m") + ".txt"), "a", encoding="utf-8") as f:
                        f.write(txt)
            if m["dateCreated"] > last:
                last, seen = m["dateCreated"], set()
            seen.add(m["guid"])
            total += 1
        if len(page) < PAGE:
            break
        off += PAGE
        save_state({"last_ts": last, "seen": sorted(seen)})
    save_state({"last_ts": last, "seen": sorted(seen)})
    return total


def main():
    if not URL or not PASSWORD:
        sys.exit("Set BB_URL and BB_PASSWORD.")
    os.makedirs(OUT, exist_ok=True)
    while True:
        try:
            n = run_once()
            log(f"saved {n} new message(s)")
        except Exception as e:
            log("error:", e)
            if ONCE:
                sys.exit(1)
        if ONCE:
            return
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
