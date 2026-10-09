<!--
  The GitHub release text for a release run of .github/workflows/ios.yml: a
  manual run of branch ios with "release" set to a tag such as ios-v0.2. The
  workflow publishes this file, as it is in the commit the run builds, as the
  release body (body_path). Update it before each release: the run stops
  before building unless this file has a "### What's in <tag>" heading line
  for that tag (for example "### What's in ios-v0.2"), written exactly like
  that and on a line of its own. A '-' in the version after "ios-"
  (ios-v0.2-beta1) makes a prerelease; without one (ios-v0.2) the release is
  marked as the latest release. Only the .ipa files named in RELEASE_IPAS in ios.yml are
  attached (for now serioussamse-ios.ipa, The Second Encounter). Links must be
  absolute: relative links don't resolve on a release page. Keep each
  paragraph and list item on one line: a release page turns every line break
  into a visible one.
-->

**Serious Sam: The Second Encounter for iOS v0.1**: an unofficial iPhone build of *Serious Sam: The Second Encounter*, running on Croteam's open-source Serious Engine 1 (by way of [tx00100xt/SeriousSamClassic](https://github.com/tx00100xt/SeriousSamClassic)), with on-screen touch controls made for it.

**You need your own copy of the game; no game files are included.** You copy the game's files from your PC copy of The Second Encounter onto your iPhone (see *Install*).

**This release is The Second Encounter only.** The First Encounter may follow in a later release.

**New here?** *Requirements* and *Install* are near the bottom of this page, just above the download.

### What's in ios-v0.1

The first public release:

- **Touch controls made for Serious Sam:** a move stick that appears under your left thumb, drag anywhere to look, and **FIRE**, **CROUCH**, **USE** and **JUMP** under your right thumb. **ZOOM** appears while you hold the sniper rifle, and **BOMB** (with how many you have) while you carry serious bombs.
- **A weapon wheel** on **NEXT WPN** and **PREV WPN**: every weapon with its HUD icon and its ammo, so you can pick the one you want. Slide to pick in one movement, or hold to open it and tap. A quick tap still switches to the next or previous weapon.
- **Tilt aiming (gyro):** aim by turning the phone, on top of dragging. It's **off** until you switch it on in MENU's hidden tray.
- **QUICK SAVE** and **QUICK LOAD** that need a short hold, so a stray touch can't save over your quick save or load an old one.
- **MENU's hidden tray** (hold **MENU**): tilt aiming's sensitivity and mode, an FPS counter, and the keyboard for the game's console.
- **The messages envelope** in the HUD's top row: tap it to mark your messages read, hold it to open NETRICSA.
- **A HUD that fits iPhone screens:** clear of the rounded corners, the notch or Dynamic Island and the home bar, with the power-ups moved to the top row and the ammo boxes at the bottom right gone (BOMB counts your bombs instead).
- **The game's menus work by tapping**, on/off options and sliders included.
- **Leaving the app pauses the game** and saves your settings (not your game: quick save first).

---

### How to play: every control explained

The touch controls appear while you're playing a single-player game, and hide in the menus, NETRICSA, the intro, demos and while a level loads (there you just tap, as you'd click with a mouse). The game runs in landscape, either way round.

Where everything is (on a phone, turn it sideways to see the whole picture):

```
 SCORE   power-ups   HIGH SCORE  envelope           QUICK  QUICK  MENU
 NEXT  PREV                                         SAVE   LOAD
 WPN   WPN                             [SENS] [GYRO] [FPS] [keyboard]
                                       (MENU's tray, while it's open)

                                                                    BOMB
                                                            JUMP
                                                   USE
     ( o )  move stick: appears                                     ZOOM
            where your left thumb lands      CROUCH         FIRE
                         [weapon and ammo]
```

Exact positions shift a little to fit your screen, the camera cutout and the HUD. ZOOM and BOMB only show when you can use them. Buttons are slightly see-through until you touch them, and a touch just beside a button still counts. While the game is paused, only **RESUME** (in the middle of the screen) and **MENU** show.

#### Moving and looking

- **Move:** put your left thumb down anywhere in the left part of the screen (a bit less than half of it). The stick appears right under your thumb and goes away when you lift it. Push up the screen to go forward.
- **Speed:** a short push is already full speed, because Sam is played running. Push only a little for slower, careful steps.
- **Look:** drag anywhere else that isn't a button, which mostly means the right side. A second finger on the left side, while your thumb is on the stick, looks too.
- **Dragging on FIRE, CROUCH, USE, JUMP or ZOOM also turns the view**, so if your thumb lands on one while you're aiming, just keep dragging. You can hold FIRE and aim with the same thumb.
- **Dragging works like the mouse**, so the game's mouse settings change it: *SENSITIVITY* and *INVERT LOOK* in *OPTIONS > PLAYERS AND CONTROLS > CUSTOMIZE CONTROLS*.
- You can also aim by turning the phone: see *Tilt aiming* below.

#### Buttons

| Button | Where | What it does |
| --- | --- | --- |
| **FIRE** | bottom right, the big one | Fires for as long as you hold it. |
| **CROUCH** | left of FIRE | Crouches while held. |
| **USE** | up and left of FIRE | Works switches. It never opens NETRICSA (that's the envelope) and never works the sniper scope (that's ZOOM). |
| **JUMP** | above FIRE | Jumps. |
| **ZOOM** | right of FIRE, only while the sniper rifle is in your hands | Tap to look through the scope, tap again to stop. Hold it while scoped to zoom in further. Like Use on PC, it works a switch instead if there's one in front of you. |
| **BOMB** | right of JUMP, only while you carry serious bombs | Shows how many you have, under the word BOMB. Sets one off when you **lift** your finger on it. Dragging on it doesn't look, so a look swipe that starts on BOMB can't waste a bomb. |
| **NEXT WPN** and **PREV WPN** | top left, below your score | Tap: next or previous weapon. Slide or hold: the weapon wheel. See *The weapon wheel* below. |
| **QUICK SAVE** and **QUICK LOAD** | top right | Hold for about a third of a second. See *Quick save and quick load* below. |
| **MENU** | top right corner | Tap: the game's menu. Hold: the hidden tray. |
| **RESUME** | middle of the screen, only while paused | Tap to carry on. |

FIRE, CROUCH, USE, JUMP and ZOOM act as soon as you touch them. BOMB, MENU, RESUME and the tray's buttons act when you **lift** your finger, so if you touch one by mistake, slide off before you lift.

The touch buttons don't go through the game's key bindings, so they keep working whatever keys you bind.

#### The weapon wheel (NEXT WPN and PREV WPN)

Both buttons have three gestures, and both open the same wheel:

- **Quick tap:** lift within about a third of a second, without sliding. NEXT WPN switches to your next weapon and PREV WPN to the previous one, as you lift. With the sniper scope on, NEXT WPN zooms out and PREV WPN zooms in instead, as on PC.
- **Slide** (the quickest way to pick): touch the button and slide your thumb away. The wheel opens **at once**. Keep sliding towards a weapon: a short slide in its direction is enough. If you can take it, its slice pops out. Its name shows in the middle, and, on iPhones with haptics, you feel a light tick. **Lift to take it.**
- **Hold:** touch and hold still for about a third of a second. A ring fills round the button, then the wheel opens and **stays open**. Lift, then **tap** a weapon to take it. (Or, without lifting, slide out to pick by sliding after all.)

Changing your mind:

- **While sliding:** lift in the **gap at the bottom** of the wheel (marked *cancel*), or back where you started. Lifting on a weapon you can't take also changes nothing. A slide too short to point at anything leaves the wheel open for tapping.
- **When it's open for tapping:** tap the middle, the gap, anywhere outside the wheel, a button, or the weapon you already hold, and the wheel closes with no change. Tapping a weapon you can't take does nothing and leaves the wheel open.

What the wheel shows:

- **One slice per weapon, 14 in all**, always in the same place, in the order NEXT WPN steps through them, clockwise from the bottom left: Knife, Chainsaw, Colt, Two Colts, Shotgun, Double Shotgun, Tommygun, Minigun, Rocket Launcher, Grenade Launcher, Flamethrower, Sniper Rifle, Lasergun, Cannon. The serious bomb isn't on the wheel: it has BOMB.
- **The weapon's own HUD icon**, with its ammo under it (up to 999). The knife, chainsaw and colts show no count. Two Colts shows the colt twice.
- **Colours:** each slice is tinted by its kind of ammo, so weapons that share ammo share a colour (the two shotguns; the tommygun and the minigun).
- **White edge, not popped out:** the weapon in your hands.
- **Greyed icon, count still shown:** you have it, but it's out of ammo, so you can't take it. The double shotgun needs two shells.
- **Faint silhouette, no count:** you haven't found it yet.
- **The middle** names the weapon you're pointing at (or the one in your hands), shows its ammo, for example *37 / 50*, and tells you what lifting will do: *lift to select*, *no ammo*, *not found yet* or *lift to cancel*. A needle at its edge shows which way your thumb points.

While it's open:

- **The game holds still**, so take your time. *Paused* doesn't show, the game's sounds stop, and the music keeps playing. Other touches and tilt aiming are ignored until the wheel closes.
- The wheel doesn't open while you're dead, during a cutscene or while the game is moving you, and it closes by itself, picking nothing, if one of those happens. It also closes when the menu, the console, NETRICSA or a quick load comes up, when the game pauses, and when you leave the app.

#### Quick save and quick load: why the short hold

**QUICK SAVE** makes a quick save and **QUICK LOAD** loads your latest one. Both need you to **hold** the button for about a **third of a second**: a ring fills round it, and when it's full the game saves or loads, once, with your finger still down.

**Why the hold?** So a stray touch can't save over your quick save, or throw away your progress by loading an old one. These buttons sit at the top of the screen next to MENU, and a quick brush past them does nothing.

- **To cancel**, lift or slide off before the ring fills. Once you've slid off it won't go off, even if you slide back on.
- **To do it again**, lift, then touch and hold again.
- **No quick save yet?** Then QUICK LOAD does nothing, and *No quicksave yet* shows for a moment at the top of the screen.
- **Normal saves:** tap MENU and use the game's own save and load screens. To save, tap `<save a new one>`, then tap it again: the save gets the name the game suggests (the level and the date). There's no keyboard in the menus, so the name can't be changed.

#### MENU and its hidden tray

**Tap MENU** for the game's menu (it opens when you lift your finger). **Hold MENU** until its ring fills (about half a second) and a small tray opens just under it instead, with four buttons, from left to right:

| Tray button | What it does |
| --- | --- |
| **SENS** | Tilt aiming's sensitivity: **1.0x**, **1.5x** (the default), **2.0x** or **3.0x**. At 1.0x the view turns as far as the phone does. Dimmed while GYRO is off. |
| **GYRO** | Tilt aiming: **OFF** (the default), **TOUCH** or **ALWAYS**. Edged in yellow while tilt aiming is on. See *Tilt aiming* below. |
| **FPS** | Shows or hides a frame-rate counter next to QUICK SAVE. Edged in yellow while it's on. |
| **Keyboard** (the keyboard symbol) | Opens the game's console with the iPhone keyboard, for console commands. |

- SENS and GYRO show their setting on the button (for example *SENS 1.5x*, *GYRO OFF*).
- Either keep your thumb down, slide it onto a tray button and lift, or lift first and then tap one.
- Each tap on **SENS** or **GYRO** moves on to the next setting, and the tray stays open so you can tap again. The tray closes after **FPS** or the keyboard, or when you touch anywhere else. That touch still counts: touching FIRE closes the tray and fires. Touching MENU again only closes it.
- If you slide off MENU while holding it, nothing happens.
- The app **remembers SENS, GYRO and FPS** for next time.
- **While the console is open**, only MENU shows, edged in yellow. Tap it (or the tray's keyboard button) to close the console and the keyboard and get back to the game.

#### Tilt aiming (gyro)

Turn and tilt the phone to aim, on top of dragging. **It starts switched off.** Hold **MENU** and tap **GYRO** to step through the settings:

- **GYRO OFF** (the default): no tilt aiming. The app doesn't read the motion sensor at all.
- **GYRO TOUCH:** turning the phone aims while **either thumb** is touching the game: your left thumb on the move stick (even resting without moving), or your right thumb on the look area (resting or dragging) or on FIRE, ZOOM, CROUCH, USE or JUMP. So with your left thumb on the stick, hopping your right thumb onto FIRE doesn't interrupt aiming. **To move the phone back to a comfortable position, lift both thumbs**: the view stays exactly where it is, like lifting a mouse off the desk, and carries on from there when you touch again. BOMB, the buttons along the top and the envelope don't count.
- **GYRO ALWAYS:** turning the phone always aims, with or without a thumb down.

Good to know:

- **The view never springs back.** There's no "straight ahead" position: however you hold the phone when you start is where you start from.
- Tilting the top edge of the screen toward you looks up, even with *INVERT LOOK* on.
- **At 1.0x the view turns as far as the phone does.** The game's mouse settings don't change tilt aiming: use **SENS**. Very slow drifts are damped on purpose, so a phone held still doesn't creep. The sniper scope's zoom slows it down, as it slows every turn.
- Tilt aiming pauses while the weapon wheel or MENU's tray is open. It's off in the menus, NETRICSA and the console, while the game is paused or loading, and while you're out of the app.
- On a device without a motion sensor, GYRO says **NO GYRO** and does nothing.

#### Messages and NETRICSA: the envelope

The HUD's messages box (an envelope with the number of unread messages) sits in the **HUD's top row, right of the high score**, instead of at the bottom right as on PC, which is under FIRE here. It blinks while you have unread messages.

- **Tap the envelope** to mark every message read, so it stops blinking. NETRICSA doesn't open. Your saves keep which messages are read.
- **Hold the envelope** until a ring fills round it (about half a second) to open **NETRICSA**. Inside NETRICSA, tap as you'd click.
- **With nothing unread**, the envelope stays, dim, with a **0**, so you can always hold it to open NETRICSA. A tap on it then does nothing.
- If your finger slides off the envelope, nothing happens.
- Until you've opened NETRICSA once, the game reminds you when a new message comes in: *Hold the envelope at the top to read the message!*
- **USE never opens NETRICSA**, however quickly you tap it twice.
- If you switch off the HUD's messages box, or the whole HUD, there's no envelope, and so no way into NETRICSA by touch.

#### The HUD

- **It fits rounded, notched screens:** the HUD, the game's messages, the clock and the stats stay clear of the rounded corners, the notch or Dynamic Island and the home bar. (The sniper scope's view still fills the whole screen.)
- **No ammo boxes at the bottom right:** that row isn't drawn, because it would be under FIRE. Your current weapon and its ammo still show at the bottom middle, as on PC, and **BOMB** shows how many serious bombs you have.
- **Power-ups** show in the top row, between the score and the high score: the same icons, bars and running-out beep as on PC.
- **The envelope** is in the top row too (see above).

#### Menus, leaving the app, and the console

- **Menus:** tap them as you'd click. A tap works on what it lands on, so on/off options such as *INVERT LOOK* and sliders such as *SENSITIVITY* can be set by touch (a slider jumps to where you tap).
- **Intro and demos:** tap to go to the main menu.
- **No typing in the menus.** No keyboard shows there, so a player name or a save's name can't be typed. Tapping the name field accepts what's there; tapping anywhere else leaves it as it was.
- **Customize Controls:** when the game asks you to press a key to bind, a tap ends the wait and keeps the old binding (touches can't be bound). You don't need to change bindings: the touch buttons don't use them.
- **Leaving the app** (going to the home screen or another app): a single-player game pauses and your settings are saved. **Your game isn't saved**, and iOS can close an app that's in the background, so quick save first if you might be away a while. When you come back, the game is paused with **RESUME** and **MENU** on screen.
- **The console:** hold MENU and tap the keyboard button. The console opens with the iPhone keyboard. Tap MENU to close it.

#### Small print

- **Weapon wheel:** if iOS cancels your touch while the wheel is open and the game stays on screen, the wheel stays open: tap a weapon, or tap anywhere else to close it.
- **Quick save and quick load:** two fingers on one button still save or load only once. With both buttons held, only the one whose ring fills first goes off, never both (if both fill at the same moment, it saves).
- **MENU's tray:** anywhere on its dark backing counts as the nearest tray button.
- **Tilt aiming:** turning left and right works however far back you tip the phone, even lying flat. It pauses for a moment after you turn the phone round to the other landscape side.

### Known limitations

- **The Second Encounter only.** The First Encounter isn't in this release, and its game files won't start this app.
- **Single player only.** The touch controls only appear in single-player games. Co-op and multiplayer have no touch controls and haven't been tested.
- **No typing in the game's menus** (player names, save names). Typing works in the console.
- **NETRICSA by touch needs the envelope**, so keep the HUD's messages box on.
- **Leaving the app doesn't save your game**, only your settings.
- **Limited testing so far:** it has been played on one iPhone. Not tried yet: iPads; older iOS versions (it's built for iOS 14 and newer); game controllers, hardware keyboards, mice and trackpads; game files from other editions (*Serious Sam Classics: Revolution*, the HD remakes, CD and non-English versions); PC saves on the phone, or phone saves on PC; restoring a backup of your saves; whether installing a newer version with your sideloading tool keeps your files.
- **The HUD on narrower iPhones:** with the HUD set larger than normal, or the legacy HUD, a layout check found that the messages count or a boss's health bar can sit under QUICK SAVE, and the armour icon under the notch or Dynamic Island. On the smallest iPhones (the size of the first iPhone SE), the messages count and the boss's health bar can sit under QUICK SAVE at the normal HUD size too. This hasn't been seen on a phone.

### Requirements

- An **iPhone on iOS 14 or newer.** The app is also marked for iPad, but it has never been installed or tried on one.
- **Your own PC copy of Serious Sam: The Second Encounter**, for its game files: the eight `.gro` files listed under *Install* and the `Help` folder, about 410 MB in the copy this was tested with. You'll need the computer it's installed on, to copy them to your iPhone.
- A **sideloading tool or signing service** (something that installs apps from outside the App Store) that can install an app file (`.ipa`) you give it, for example Signulous. The `.ipa` isn't signed for your iPhone, so it can't be installed without one.

### Install

1. Download **`serioussamse-ios.ipa`** below.
2. Install it with your sideloading tool or signing service, following that tool's own instructions (whether iOS asks you to trust a developer or to turn on Developer Mode depends on the tool). On your home screen the app is called **Sam SE**. Its version is 0.1 followed by a build number.
3. **Open Sam SE once.** With no game files yet, it shows a *Fatal Error* box saying *Game data not found*. Tap OK and the app closes. That's expected: by then the app has made its folder for your files.
4. On your computer, open the folder The Second Encounter is installed in, and find:
   - all the `.gro` files: `SE1_00.gro`, `SE1_00_Extra.gro`, `SE1_00_ExtraTools.gro`, `SE1_00_Levels.gro`, `SE1_00_Logo.gro`, `SE1_00_Music.gro`, `1_04_patch.gro` and `1_07_tools.gro`
   - the `Help` folder, and a `Levels` folder if your game folder has one.

   You don't need `Bin` or any of the other folders. Not sure where the game is installed? Search your computer for `SE1_00_Levels.gro`: the folder it's in is the one.
5. Copy them into the Files app's **On My iPhone > Sam SE**, **directly** into that folder (not inside another folder, and not as a `.zip`), with their names unchanged. Use whatever way you like to get files into the Files app, for example iCloud Drive: copy them into iCloud Drive on your computer, then move them into Sam SE in the Files app. `SE1_10b.gro`, `ModEXT.txt` and two `.log` files are already there: the app makes them itself, so leave them.
6. **Open Sam SE again.** If the intro plays, tap to get to the main menu.

**If the game files are missing:** if Sam SE can't find `SE1_00_Levels.gro` directly in its folder, it shows the *Fatal Error* box, *Game data not found*, naming the missing file, and closes when you tap OK. Check that the files are directly in *On My iPhone > Sam SE*, not in a folder inside it and not zipped, with their names unchanged, then open the app again. The app checks only for that one file, so also make sure all eight `.gro` files from step 4 are there.

**Your saves** are in the Files app, in *On My iPhone > Sam SE > SaveGame > Player0*, with quick saves in its `Quick` folder. Your player profile is in *Sam SE > Players*.

- **Back up** now and then by copying `SaveGame` and `Players` somewhere safe (for example iCloud Drive), and always before you delete or reinstall the app: deleting the app deletes its folder, game files and saves included.
- The SENS, GYRO and FPS settings are kept by iOS, not in the Sam SE folder.
- **If something goes wrong:** `SeriousSam.log` and `Output.log`, directly in *Sam SE* (next to the `.gro` files), say what the game was doing. Copy them out before you open the app again, because each start empties them. **Found a bug?** Report it at https://github.com/sithewok13-dev/SeriousSamClassic/issues with both log files attached, and say which iPhone and iOS version you have and what you were doing. It's an iOS build of its own, so please report its problems there, not to the upstream SeriousSamClassic project.

**Download:** `serioussamse-ios.ipa`, under *Assets* below. It's The Second Encounter; this release has no First Encounter file. The *iOS latest build* prerelease, also on the Releases page, is rebuilt automatically after every code change, before anyone has tried it, and its First Encounter file has never been played: use this release.

---

Unofficial build. Serious Sam: The Second Encounter and Serious Engine 1 are by Croteam, who released the engine's source code (Serious Engine 1.10) under the GNU GPL v2. This build is based on [tx00100xt/SeriousSamClassic](https://github.com/tx00100xt/SeriousSamClassic). It is not an official Croteam release, and it is not affiliated with or endorsed by Croteam or Devolver Digital. No game files are included.

This app is free software under the GNU GPL v2 (https://github.com/sithewok13-dev/SeriousSamClassic/blob/ios/LICENSE). Its source code, iOS changes included, is the `ios` branch: https://github.com/sithewok13-dev/SeriousSamClassic/tree/ios (this release is the tag `ios-v0.1`: https://github.com/sithewok13-dev/SeriousSamClassic/tree/ios-v0.1).

The app also includes libraries under their own licences: SDL2 (zlib licence, https://github.com/libsdl-org/SDL/blob/release-2.30.8/LICENSE.txt), gl4es (MIT licence, https://github.com/ptitSeb/gl4es/blob/ec16bedd8819c475326f4f1a3063772c6d986e06/LICENSE), which turns the engine's OpenGL into the iPhone's OpenGL ES, and libogg and libvorbis by the Xiph.Org Foundation (BSD-style licence, https://github.com/sithewok13-dev/SeriousSamClassic/blob/ios/SamTSE/Sources/External/libvorbis/COPYING and https://github.com/sithewok13-dev/SeriousSamClassic/blob/ios/SamTSE/Sources/External/libogg/COPYING), which decode the music.

<details>
<summary>Licence notices</summary>

**Serious Engine 1** (GNU GPL v2):

Copyright (c) 2002-2012 Croteam Ltd. This program is free software; you can redistribute it and/or modify it under the terms of version 2 of the GNU General Public License as published by the Free Software Foundation. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

**gl4es** (MIT licence):

Copyright (c) 2016-2018 Sebastien Chevalier

Copyright (c) 2013-2016 Ryan Hileman

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

**libogg** (BSD-style licence):

Copyright (c) 2002, Xiph.org Foundation

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
- Neither the name of the Xiph.org Foundation nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \`\`AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

**libvorbis** (BSD-style licence):

Copyright (c) 2002-2015 Xiph.org Foundation

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
- Neither the name of the Xiph.org Foundation nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \`\`AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

**SDL2** (zlib licence): Copyright (C) 1997-2024 Sam Lantinga.

</details>
