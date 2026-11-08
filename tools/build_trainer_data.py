#!/usr/bin/env python3
"""Build TrainerData.lua: every class spell a trainer teaches on Forever,
with the level of each rank, from ForeverChanges.

The addon's Trainer Preview learns a trainer's list by standing at the
trainer. That tells it prices and what the character has learned, but
nothing before the first visit, and nothing about which lines are class
spells at all (a trainer window can hold recipes and pet abilities too).
This catalog fills those gaps. Prices and learned state still come from
the client; the catalog never says what a trainer sells today, only what
ForeverChanges lists for the class.

Forever sources only (Jonatan, 06.11.2026). Source pages:

    https://foreverchanges.pro/spellbook/<class>/levels

one per class, allowed by the site's robots.txt (only /api/, /search and
/spell/ are disallowed). Fetched with a 0.7 s pause between pages. Pass
--cache DIR to read pages saved there instead of fetching (and to save
fetched pages there).

Usage:
    python3 tools/build_trainer_data.py -o TrainerData.lua
    python3 tools/build_trainer_data.py --cache /tmp/fc -o TrainerData.lua

Page structure read (as of 2026-11-08): one <section class="tl-visit"> per
level with an <h3> "Level N"; inside it one <button class="v2-row"> per
spell new at that level, with the name in <strong>, the school in
<small class="sbk-row-facts"> and tags in <span class="v2-tag ...">
("Talent": comes with the talent point; "New": not in Classic), and one
<div class="tl-ranks"> with <span>Name</span><small>Rank N</small> for
every higher rank taught at that level. A spell new at a level is its
rank 1. The page build is read from "Build x.y.z.nnnnn" in the header.
"""

import argparse
import datetime
import html
import re
import sys
import time
import urllib.request
from pathlib import Path

CLASSES = [
    ("WARRIOR", "warrior"),
    ("PALADIN", "paladin"),
    ("HUNTER", "hunter"),
    ("ROGUE", "rogue"),
    ("PRIEST", "priest"),
    ("SHAMAN", "shaman"),
    ("MAGE", "mage"),
    ("WARLOCK", "warlock"),
    ("DRUID", "druid"),
]
URL = "https://foreverchanges.pro/spellbook/{slug}/levels"
USER_AGENT = "UlRemedyForever build_trainer_data (addon data build, 0.7 s pause)"
PAUSE = 0.7

SECTION_RE = re.compile(
    r'<section class="tl-visit"[^>]*>\s*<h3[^>]*><span>Level (\d+)</span></h3>(.*?)</section>', re.S)
ROW_RE = re.compile(r'<button class="v2-row[^"]*"[^>]*>(.*?)</button>', re.S)
NAME_RE = re.compile(r"<strong>(.*?)</strong>", re.S)
TAG_RE = re.compile(r'<span class="v2-tag ([^"]*)">([^<]*)</span>')
RANKS_RE = re.compile(r'<div class="tl-ranks">(.*?)</div>\s*</div>', re.S)
RANK_RE = re.compile(r"<span>([^<]*)</span>\s*<small>Rank (\d+)</small>")
BUILD_RE = re.compile(r"Build (\d+\.\d+\.\d+\.\d+)")


def fetch(slug, cache):
    path = cache / f"{slug}-levels.html" if cache else None
    if path and path.exists():
        return path.read_text(encoding="utf-8")
    req = urllib.request.Request(URL.format(slug=slug), headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        text = resp.read().decode("utf-8")
    if path:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    time.sleep(PAUSE)
    return text


def clean(text):
    return html.unescape(re.sub(r"<[^>]+>", "", text)).strip()


def parse(page, class_key):
    """Returns ({name: {"levels": {rank: level}, "talent": bool, "new": bool}}, build)."""
    spells = {}
    build = BUILD_RE.search(page)
    sections = SECTION_RE.findall(page)
    if not sections:
        raise SystemExit(f"{class_key}: no level sections found, the page structure has changed")
    for level, body in sections:
        level = int(level)
        for row in ROW_RE.findall(body):
            m = NAME_RE.search(row)
            if not m:
                continue
            name = clean(m.group(1))
            tags = {clean(t) for _, t in TAG_RE.findall(row)}
            spell = spells.setdefault(name, {"levels": {}, "talent": False, "new": False})
            if 1 in spell["levels"]:
                print(f"  {class_key}: {name} is new at level {level} and again at "
                      f"{spell['levels'][1]}, keeping the lower", file=sys.stderr)
                spell["levels"][1] = min(spell["levels"][1], level)
            else:
                spell["levels"][1] = level
            spell["talent"] = spell["talent"] or "Talent" in tags
            spell["new"] = spell["new"] or "New" in tags
        for ranks in RANKS_RE.findall(body):
            for name, rank in RANK_RE.findall(ranks):
                name, rank = clean(name), int(rank)
                spell = spells.setdefault(name, {"levels": {}, "talent": False, "new": False})
                if rank in spell["levels"] and spell["levels"][rank] != level:
                    print(f"  {class_key}: {name} rank {rank} at level {level} and "
                          f"{spell['levels'][rank]}, keeping the lower", file=sys.stderr)
                    spell["levels"][rank] = min(spell["levels"][rank], level)
                else:
                    spell["levels"][rank] = level
    return spells, (build.group(1) if build else None)


def check(class_key, spells):
    """Ranks must run 1..n without holes, or the Lua list would have nils.

    A spell whose page entries start at rank 2 is a starting spell: rank 1
    is known at character creation and no trainer lists it, so the page
    has no level for it. It is filed at level 1, which is when it is had.
    """
    ok = True
    for name, spell in spells.items():
        if 1 not in spell["levels"] and 2 in spell["levels"]:
            spell["levels"][1] = 1
            spell["starting"] = True
            print(f"  {class_key}: {name} starts at rank 2 on the page, rank 1 filed as a starting spell", file=sys.stderr)
        ranks = sorted(spell["levels"])
        if ranks != list(range(1, len(ranks) + 1)):
            print(f"  {class_key}: {name} has ranks {ranks}, expected 1..{len(ranks)}", file=sys.stderr)
            ok = False
        levels = [spell["levels"][r] for r in ranks]
        if levels != sorted(levels):
            print(f"  {class_key}: {name} ranks are not in level order: {levels}", file=sys.stderr)
    return ok


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit(classes, build, fetched, out):
    lines = []
    lines.append("-- TrainerData: every class spell a trainer teaches on Forever, with the")
    lines.append("-- level of each rank. Generated by tools/build_trainer_data.py, do not")
    lines.append("-- edit by hand.")
    lines.append("--")
    lines.append("-- Source: ForeverChanges, https://foreverchanges.pro/spellbook/<class>/levels")
    lines.append(f"-- Build {build or 'unknown'}, fetched {fetched}.")
    lines.append("--")
    lines.append("-- UlRemedy.TrainerData.classes[CLASS][name] is a list of levels, one per")
    lines.append("-- rank (index 1 is rank 1). talent = true: rank 1 comes with the talent")
    lines.append("-- point, not from a trainer. new = true: not in Classic. starting = true:")
    lines.append("-- rank 1 is known at character creation (filed at level 1), trainers")
    lines.append("-- list it from rank 2.")
    lines.append("")
    lines.append("UlRemedy.TrainerData = {")
    lines.append(f"    build = {lua_string(build or '')},")
    lines.append(f"    fetched = {lua_string(fetched)},")
    lines.append("    classes = {")
    for class_key, _ in CLASSES:
        spells = classes[class_key]
        lines.append(f"        {class_key} = {{")
        for name in sorted(spells):
            spell = spells[name]
            levels = [str(spell["levels"][r]) for r in sorted(spell["levels"])]
            extra = ""
            if spell["talent"]:
                extra += ", talent = true"
            if spell["new"]:
                extra += ", new = true"
            if spell.get("starting"):
                extra += ", starting = true"
            lines.append(f"            [{lua_string(name)}] = {{ {', '.join(levels)}{extra} }},")
        lines.append("        },")
    lines.append("    },")
    lines.append("}")
    lines.append("")
    Path(out).write_text("\n".join(lines), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", type=Path, help="directory of saved <class>-levels.html pages")
    ap.add_argument("-o", "--out", default="TrainerData.lua")
    args = ap.parse_args()

    classes, builds = {}, set()
    for class_key, slug in CLASSES:
        page = fetch(slug, args.cache)
        spells, build = parse(page, class_key)
        if build:
            builds.add(build)
        if not check(class_key, spells):
            raise SystemExit(f"{class_key}: rank holes, see above")
        classes[class_key] = spells
        ranks = sum(len(s["levels"]) for s in spells.values())
        talents = sum(1 for s in spells.values() if s["talent"])
        print(f"{class_key}: {len(spells)} spells, {ranks} ranks, {talents} from talents")
    if len(builds) > 1:
        print(f"warning: pages report different builds: {sorted(builds)}", file=sys.stderr)
    build = sorted(builds)[-1] if builds else None
    fetched = datetime.date.today().isoformat()
    emit(classes, build, fetched, args.out)
    print(f"wrote {args.out} (build {build}, {fetched})")


if __name__ == "__main__":
    main()
