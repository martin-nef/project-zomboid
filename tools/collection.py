#!/usr/bin/env python3
"""Regenerates the mod lines of deploy/server.ini from a Workshop collection.

Reads tools/mods.conf, lists the collection's items, downloads them with
steamcmd (podman, cm2network/steamcmd) into a cache directory, reads every
mod's Build 42 mod.info and rewrites Mods= (in dependency order),
WorkshopItems= and Map= in deploy/server.ini. Prints what changed and anything
that needs a human: requirements no enabled mod provides, and server-side Java
mods whose item isn't in ZB_APPROVED_ITEMS (deploy/config.env).

    tools/collection.py              # download (about 10 min for 3.6 GB) and regenerate
    tools/collection.py --no-download  # reuse the cache, e.g. after editing mods.conf
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONF = REPO / "tools" / "mods.conf"
SERVER_INI = REPO / "deploy" / "server.ini"
CONFIG_ENV = REPO / "deploy" / "config.env"
BASE_MAP = "Muldraugh, KY"
STEAMCMD_IMAGE = "docker.io/cm2network/steamcmd:latest"


def read_conf():
    conf = {"collection": None, "item": [], "exclude": set(), "first": []}
    for line in CONF.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        key, _, value = line.partition(" ")
        value = value.strip()
        if key == "collection":
            conf["collection"] = value
        elif key in ("item", "first"):
            conf[key].append(value)
        elif key == "exclude":
            conf["exclude"].add(value)
        else:
            sys.exit(f"mods.conf: unknown key {key!r}")
    return conf


def fetch(url, *form):
    # curl rather than urllib: Steam Community answers urllib with 429.
    args = [a for f in form for a in ("-d", f)]
    return subprocess.run(["curl", "-fsSL", "--max-time", "30", *args, url],
                          capture_output=True, text=True, check=True).stdout


def collection_items(collection_id):
    # The API only answers for public collections; unlisted ones (like ours)
    # come back with result 9, so fall back to the collection's web page.
    details = json.loads(fetch("https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/",
                               "collectioncount=1", f"publishedfileids[0]={collection_id}"))
    details = details["response"]["collectiondetails"][0]
    if details.get("result") == 1:
        return [c["publishedfileid"] for c in details["children"]]
    url = f"https://steamcommunity.com/sharedfiles/filedetails/?id={collection_id}"
    ids = list(dict.fromkeys(re.findall(r'id="sharedfile_(\d+)"', fetch(url))))
    if not ids:
        sys.exit(f"no items found on {url}")
    return ids


def download(items, cache):
    cache.mkdir(parents=True, exist_ok=True)
    args = []
    for item in items:
        args += ["+workshop_download_item", "108600", item]
    cmd = ["podman", "run", "--rm", "--userns=keep-id", "-v", f"{cache}:/ws:Z", STEAMCMD_IMAGE,
           "/home/steam/steamcmd/steamcmd.sh", "+force_install_dir", "/ws", "+login", "anonymous", *args, "+quit"]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    done = set(re.findall(r"Success\. Downloaded item (\d+)", out))
    missing = [i for i in items if i not in done]
    if missing:
        sys.exit(f"steamcmd didn't download {', '.join(missing)}; run again")


def version_key(name):
    return tuple(int(p) for p in name.split("."))


def mod_dirs(mod_root, game_version):
    """The folders Build 42 reads a mod from: common/, then the newest
    versioned folder not newer than the game. Old flat mods have neither."""
    versioned = [d for d in mod_root.iterdir() if d.is_dir() and re.fullmatch(r"\d+(\.\d+)*", d.name)]
    versioned = [d for d in versioned if version_key(d.name) <= game_version]
    dirs = [mod_root / "common"] if (mod_root / "common").is_dir() else []
    if versioned:
        dirs.append(max(versioned, key=lambda d: version_key(d.name)))
    return dirs or [mod_root]


def id_list(value):
    return [v.strip().lstrip("\\").strip() for v in value.split(",") if v.strip().lstrip("\\").strip()]


def read_mods(item, cache, game_version):
    mods = []
    root = cache / "steamapps" / "workshop" / "content" / "108600" / item / "mods"
    for mod_root in sorted(p for p in root.iterdir() if p.is_dir()):
        dirs = mod_dirs(mod_root, game_version)
        info = {}
        for d in dirs:  # the versioned mod.info wins over common's
            f = d / "mod.info"
            if f.is_file():
                for line in f.read_text("utf-8", "replace").splitlines():
                    k, sep, v = line.partition("=")
                    if sep:
                        info[k.strip().lower()] = v.strip()
        if "id" not in info:
            continue
        jar = info.get("javajarfile", "")
        mods.append({
            "id": info["id"],
            "item": item,
            "require": id_list(info.get("require", "")),
            "after": id_list(info.get("loadmodafter", "")),
            "before": id_list(info.get("loadmodbefore", "")),
            # ZombieBuddy's own jar is the loader itself, signed and trusted
            # through ZB_TRUSTED_AUTHORS.
            "server_jar": bool(jar) and "media/java/client/" not in jar and info["id"] != "ZombieBuddy",
            "maps": sorted({m.name for d in dirs for m in (d / "media" / "maps").glob("*") if m.is_dir()}),
        })
    return mods


def load_order(mods, first):
    """Topological sort over require/loadModAfter/loadModBefore. Among mods
    that are free to go next, `first` mods win, then mods other mods depend on
    (frameworks, so add-ons that forgot to declare them still come later),
    then the collection's order."""
    ids = [m["id"] for m in mods]
    needed = {d for m in mods for d in m["require"] + m["after"]}
    rank = {i: (first.index(i) if i in first else len(first), i not in needed, n) for n, i in enumerate(ids)}
    preds = {i: set() for i in ids}
    for m in mods:
        for dep in m["require"] + m["after"]:
            if dep in preds and dep != m["id"]:
                preds[m["id"]].add(dep)
        for later in m["before"]:
            if later in preds and later != m["id"]:
                preds[later].add(m["id"])
    order, placed = [], set()
    while len(order) < len(ids):
        ready = [i for i in ids if i not in placed and preds[i] <= placed]
        if not ready:
            sys.exit("load order cycle among: " + ", ".join(i for i in ids if i not in placed))
        nxt = min(ready, key=rank.get)
        order.append(nxt)
        placed.add(nxt)
    return order


def set_ini_line(text, key, value):
    line = f"{key}={value}"
    pattern = re.compile(rf"^{re.escape(key)}=.*$", re.M)
    if pattern.search(text):
        return pattern.sub(lambda _: line, text)
    return text.rstrip("\n") + "\n" + line + "\n"


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--cache", type=Path, default=Path.home() / ".cache" / "pz-collection")
    p.add_argument("--no-download", action="store_true", help="reuse the cached items")
    p.add_argument("--game-version", default="42.21", help="game version to resolve mod folders for")
    a = p.parse_args()

    conf = read_conf()
    items = list(dict.fromkeys(collection_items(conf["collection"]) + conf["item"]))
    print(f"collection {conf['collection']}: {len(items)} items")
    if not a.no_download:
        download(items, a.cache.resolve())

    all_mods = [m for item in items for m in read_mods(item, a.cache, version_key(a.game_version))]
    empty = sorted(set(items) - {m["item"] for m in all_mods})
    if empty:
        sys.exit(f"no Build 42 mods found in item(s) {', '.join(empty)} (not downloaded?)")
    mods = [m for m in all_mods if m["id"] not in conf["exclude"]]
    by_id = {m["id"]: m for m in mods}
    order = load_order(mods, conf["first"])

    problems = []
    for m in mods:
        for dep in m["require"]:
            if dep not in by_id:
                problems.append(f"{m['id']} ({m['item']}) requires {dep}, which no enabled mod provides")
    env = dict(l.split("=", 1) for l in CONFIG_ENV.read_text().splitlines() if "=" in l and not l.startswith("#"))
    approved = set(env.get("ZB_APPROVED_ITEMS", "").split())
    for item in sorted({m["item"] for m in mods if m["server_jar"]} - approved):
        names = ", ".join(m["id"] for m in mods if m["item"] == item and m["server_jar"])
        problems.append(f"item {item} has server-side Java ({names}) but isn't in ZB_APPROVED_ITEMS")
    for item in sorted(approved - {m["item"] for m in mods if m["server_jar"]}):
        problems.append(f"ZB_APPROVED_ITEMS lists {item}, which has no enabled server-side Java mod")

    maps = [mp for i in order for mp in by_id[i]["maps"]]
    ini = SERVER_INI.read_text()
    old_items = set(re.search(r"^WorkshopItems=(.*)$", ini, re.M).group(1).split(";")) - {""}
    ini = set_ini_line(ini, "Mods", ";".join("\\" + i for i in order))
    ini = set_ini_line(ini, "WorkshopItems", ";".join(items))
    ini = set_ini_line(ini, "Map", ";".join(list(dict.fromkeys(maps)) + [BASE_MAP]))
    SERVER_INI.write_text(ini)

    print(f"{len(order)} mods enabled, {len(all_mods) - len(mods)} excluded by mods.conf")
    for label, ids in (("added", set(items) - old_items), ("removed", old_items - set(items))):
        if ids:
            print(f"items {label}: {' '.join(sorted(ids))}")
    for line in problems:
        print("CHECK:", line)
    print(f"wrote {SERVER_INI.relative_to(REPO)}")


if __name__ == "__main__":
    main()
