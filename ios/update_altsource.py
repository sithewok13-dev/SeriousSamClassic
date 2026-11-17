#!/usr/bin/env python3
"""Add a release to the AltStore / SideStore source (altsource.json).

The release run of .github/workflows/ios.yml calls this after it has
published an ios-v* release, with the .ipa files it just attached (those in
RELEASE_IPAS: serioussam-ios.ipa is Sam FE, serioussamse-ios.ipa Sam SE):

    python3 ios/update_altsource.py --source altsource.json \
        --tag ios-v0.4 --notes ios/RELEASE_NOTES.md \
        --ipa serioussam-ios.ipa --ipa serioussamse-ios.ipa

For each .ipa it reads the bundle id, version, build number and minimum iOS
version from the app's own Info.plist, finds the app in the source by its
bundle id, and puts a new entry at the top of its "versions" list: the size
and SHA-256 of the file, the date, a download link to that release's asset,
and a short summary of the "New since" list from the release notes,
with a link to the release page.

AltStore and SideStore refuse a download whose version and build number
differ from the entry's, so those come from the file itself. They also tell
versions apart by version plus build number, so an older entry with the same
pair, or one for the same tag (a re-run of a release), is replaced instead of
kept twice. An entry that downloads from the ios-latest test build (whose
file changes with every push) is dropped once a numbered release is there.
Standard library only. Exits non-zero, leaving the file as it
was, if anything doesn't add up.
"""

import argparse
import datetime
import hashlib
import json
import os
import plistlib
import re
import sys
import tempfile
import zipfile

DOWNLOAD = "https://github.com/{repo}/releases/download/{tag}/{asset}"
MAX_ITEMS = 8
MAX_CHARS = 1200


def read_ipa(path):
    """Info.plist of the one .app in Payload/, plus size and SHA-256."""
    with zipfile.ZipFile(path) as z:
        names = [n for n in z.namelist()
                 if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        if len(names) != 1:
            raise SystemExit(f"{path}: expected one Payload/*.app/Info.plist, found {len(names)}")
        info = plistlib.loads(z.read(names[0]))
    sha = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            sha.update(block)
    for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
        if not isinstance(info.get(key), str) or not info[key]:
            raise SystemExit(f"{path}: Info.plist has no {key}")
    return info, os.path.getsize(path), sha.hexdigest()


def plain(text):
    """Markdown to plain text: links to their text, no bold, italics or code marks."""
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"\*\*|__|`", "", text)
    text = re.sub(r"(?<![\w*])\*([^*]+)\*(?![\w*])", r"\1", text)
    return " ".join(text.split())


def summary(notes_path, tag, repo):
    """The 'New since' list under '### What's in <tag>', one short line per item."""
    with open(notes_path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    heading = f"### What's in {tag}"
    if heading not in lines:
        raise SystemExit(f"{notes_path}: no line {heading!r}")
    items, intro = [], None
    for line in lines[lines.index(heading) + 1:]:
        if line.startswith("### ") or line.strip() == "---":
            break
        if items and not line.startswith("- ") and line.strip():
            break  # the next "Added in ..." paragraph: older releases
        if line.startswith("- "):
            item = line[2:]
            bold = re.match(r"\*\*(.+?)\*\*", item)
            if bold:
                # The bold lead phrase is the item's own headline
                item = bold.group(1)
            else:
                item = re.split(r"(?<=[.!?])\s", plain(item), maxsplit=1)[0]
            items.append("- " + plain(item).strip().rstrip(":,").strip())
        elif line.strip() and intro is None:
            intro = plain(line)
    if not items:
        raise SystemExit(f"{notes_path}: no list items under {heading!r}")
    text = "\n".join(([intro] if intro else []) + items[:MAX_ITEMS])
    if len(text) > MAX_CHARS:
        text = text[:MAX_CHARS - 1].rsplit("\n", 1)[0] + "\n..."
    return text + f"\n\nFull notes: https://github.com/{repo}/releases/tag/{tag}"


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--source", required=True)
    p.add_argument("--tag", required=True)
    p.add_argument("--notes", required=True)
    p.add_argument("--ipa", action="append", required=True)
    p.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "sithewok13-dev/SeriousSamClassic"))
    p.add_argument("--date", help="ISO 8601 (default: now, UTC)")
    a = p.parse_args()

    if not re.fullmatch(r"ios-v[0-9][0-9A-Za-z.\-]*", a.tag):
        raise SystemExit(f"tag {a.tag!r} doesn't look like a release tag (ios-v...)")
    date = a.date or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    notes = summary(a.notes, a.tag, a.repo)

    with open(a.source, encoding="utf-8") as f:
        source = json.load(f)
    apps = {app["bundleIdentifier"]: app for app in source.get("apps", [])}

    for ipa in a.ipa:
        info, size, sha = read_ipa(ipa)
        bundle_id = info["CFBundleIdentifier"]
        app = apps.get(bundle_id)
        if app is None:
            raise SystemExit(f"{ipa}: bundle id {bundle_id} isn't in {a.source}")
        entry = {
            "version": info["CFBundleShortVersionString"],
            "buildVersion": info["CFBundleVersion"],
            "marketingVersion": a.tag,
            "date": date,
            "localizedDescription": notes,
            "downloadURL": DOWNLOAD.format(repo=a.repo, tag=a.tag, asset=os.path.basename(ipa)),
            "size": size,
            "sha256": sha,
        }
        if info.get("MinimumOSVersion"):
            entry["minOSVersion"] = info["MinimumOSVersion"]
        same = lambda v: (v.get("marketingVersion") == a.tag or
                          (v.get("version"), v.get("buildVersion")) == (entry["version"], entry["buildVersion"]) or
                          "/releases/download/ios-latest/" in v.get("downloadURL", ""))
        # Newest first, by build number (each CI run's own, rising): a re-run of
        # an older release goes back in its place, not on top
        def build(v):
            try: return int(v.get("buildVersion", 0))
            except (TypeError, ValueError): return 0
        app["versions"] = sorted([entry] + [v for v in app.get("versions", []) if not same(v)],
                                 key=build, reverse=True)
        # The newest, for older AltStore and SideStore versions that only read
        # these app-level keys
        top = app["versions"][0]
        app.update(version=top["version"], versionDate=top["date"],
                   versionDescription=top["localizedDescription"],
                   downloadURL=top["downloadURL"], size=top["size"])
        print(f"{bundle_id}: {a.tag} = {entry['version']} ({entry['buildVersion']}), {size} bytes")

    tmp = tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False,
                                      dir=os.path.dirname(os.path.abspath(a.source)))
    with tmp:
        json.dump(source, tmp, indent=2, ensure_ascii=False)
        tmp.write("\n")
    os.replace(tmp.name, a.source)


if __name__ == "__main__":
    sys.exit(main())
