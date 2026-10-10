# Serious Sam Classic for iOS: notes for Claude Code sessions

Unofficial iPhone builds of Serious Sam: The First Encounter (app **Sam FE**) and
The Second Encounter (app **Sam SE**), on Croteam's open-source Serious Engine 1,
with touch controls. The owner plays them on an iPhone, isn't a programmer, and
reads everything on a phone.

- **Build branch:** `ios`. Upstream's `main` is left alone.
- **iOS code** is in `ios/`. `IOSTouch.m` / `IOSTouch.h` are the overlay (a C core
  plus a UIKit view). `patch_engine.py` holds every game-side change as idempotent
  anchored hunks: re-run it and commit the patched sources with it.
  `ios_app.cmake` sets names, bundle ids and icons. `RELEASE_NOTES.md` is the
  release text and full player guide.
- **CI:** `.github/workflows/ios.yml` (`RELEASE_IPAS`, `RELEASE_TITLE`).

**First, read the house style guide** in the owner's private files repo
(`docs/HOUSE_STYLE.md`), if you have access. The rules below apply even without it.

## Rules

- **Pushing publishes.** A push to `ios` updates the public `ios-latest` prerelease.
  Push only reviewed work, when the owner wants a test build. Back up unreviewed work
  as a patch in the owner's private files repo (that also answers the
  uncommitted-changes stop hook).
- **Releases:**
  - `ios-vX.Y` tags, made by a manual run of `ios.yml` on `ios` with input
    `release=<tag>` (`gh workflow run ios.yml --ref ios -f release=<tag>`). Only the
    IPAs in `RELEASE_IPAS` are attached. Commit and push the notes only after the
    owner's go. The notes need
    the exact line `### What's in <tag>`, one line per paragraph or list item, and
    absolute links.
  - **Before any public release or public text,** build a preview (phone and desktop
    widths) and wait for the owner's explicit go, such as "Publish ios-v0.3".
  - After publishing, download the IPAs and verify: bundle ids, no game data (only
    the bundled `SE1_10b.gro` and `ModEXT.txt`), the new code present, Latest
    marked, the tag on the built commit.
- **Game data:** never commit, upload, bundle or publish the game's files
  (installers, Croteam's `.gro` files, levels, extracted folders, zips), here or
  anywhere public. Work on local copies only.
- **Commits:**
  - Identity `Claude <noreply@anthropic.com>` (already configured); never the
    owner's email or name. Subject `iOS: ...`, then a plain wrapped body.
  - End with the attribution trailer lines your session provides. Apart from those,
    no AI model names in commits, code or docs.
  - No PRs unless asked. Never stash, reset or check out over a working tree that
    another job may be editing.
- **Touch controls standard** (shared with the owner's other ports; keep it the same):
  - Move stick where the left thumb lands; drag elsewhere to look.
  - QUICK SAVE / QUICK LOAD: a 0.3 s hold with a ring. Sliding off cancels; QUICK
    SAVE wins a tie.
  - MENU: tap = game menu; hold 0.45 s = tray with SENS, GYRO, FPS, keyboard.
  - GYRO: OFF (default) / TOUCH (aims while either thumb is down; lifting both
    freezes the view) / ALWAYS. SENS 1.0/1.5/2.0/3.0, default 1.5. Remembered.
  - NEXT WPN / PREV WPN: tap = next/previous; a 10 pt slide opens the weapon wheel at
    once; a 0.3 s hold opens it to tap. One slice per weapon (HUD icon, ammo); out of
    ammo greyed, not found faint; bottom gap cancels; the game holds still while it's
    open (music plays on); a haptic tick per slice.
  - Envelope: tap = mark read, hold = NETRICSA. USE never opens NETRICSA. BOMB shows
    the bomb count. No corner ammo row.
  - HUD clear of the corners, the notch or Dynamic Island, and the home bar. Don't
    move the right-hand buttons closer to the edge for now (the owner's request).
- **Testing:** a real-engine Linux rig (real data, local only; real overlay on a
  mock UIKit), harness, iOS SDK compiles, then independent reviews and a fix pass.
  The owner tests on the device. Say plainly what wasn't tested.
- **Lean mode:** small contexts, no full dumps (grep/sed/head/tail), reuse builds.
- **Talking to the owner:** plain words, short messages, direct links, honesty about
  mistakes and untested things. A skipped question means: use a sensible default
  and say which.
