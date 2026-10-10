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
  attached (since ios-v0.2 both: serioussamse-ios.ipa, The Second Encounter,
  and serioussam-ios.ipa, The First Encounter). Links must be
  absolute: relative links don't resolve on a release page. Keep each
  paragraph and list item on one line: a release page turns every line break
  into a visible one.
-->

**Serious Sam Classic for iOS v0.2**: unofficial iPhone builds of *Serious Sam: The First Encounter* and *Serious Sam: The Second Encounter*, running on Croteam's open-source Serious Engine 1 (by way of [tx00100xt/SeriousSamClassic](https://github.com/tx00100xt/SeriousSamClassic)), with on-screen touch controls made for them.

**You need your own copy of the game; no game files are included.** You copy the game's files from your PC copy of The First Encounter or The Second Encounter onto your iPhone (see *Install*).

**Two apps, one for each game:** **Sam FE** (`serioussam-ios.ipa`) plays The First Encounter, and **Sam SE** (`serioussamse-ios.ipa`) plays The Second Encounter. Install the one for the game you have, or both. **Sam FE is new in this release.** It has been played on an iPhone and tested on a computer, but it has had less testing than Sam SE so far (see *Known limitations*). If something goes wrong in it, please report it (see *Found a bug?*).

**New here?** *Known limitations*, *Requirements* and *Install* are near the bottom of this page, just above the download.

### What's in ios-v0.2

**New since ios-v0.1: The First Encounter**, as an app of its own, **Sam FE**, with the same touch controls as The Second Encounter. What's different in it:

- **No ZOOM and no BOMB:** The First Encounter has no sniper rifle and no serious bombs, so those two buttons never show. Their places, right of FIRE and right of JUMP, are just look area, and the other buttons don't move to fill them.
- **Its own weapon wheel**, with 11 slices for its 11 weapons: Knife, Colt, Two Colts, Shotgun, Double Shotgun, Tommygun, Minigun, Rocket Launcher, Grenade Launcher, Lasergun and Cannon. There's no chainsaw, flamethrower or sniper rifle in The First Encounter.
- **No power-ups** in the HUD's top row: The First Encounter has none.
- **NETRICSA opens by itself at the start of a level**, with the level's briefing, as on PC: tap **Exit**, at its top right, to play. On the first level, a long flyover comes before it: as on PC, FIRE or USE skips the flyover only at some points in it, so if a tap doesn't skip it, wait a little and try again, or watch it to the end.
- **Its levels aren't inside its `.gro` files:** they're in the game's `Levels` folder, so Sam FE needs that folder copied too (see *Install*).

**The Second Encounter app is unchanged:** Sam SE is the same code as in ios-v0.1, just built again. If you already have Sam SE from ios-v0.1, you don't need to install it again.

Both apps have:

- **Touch controls made for Serious Sam:** a move stick that appears under your left thumb, drag anywhere to look, and **FIRE**, **CROUCH**, **USE** and **JUMP** under your right thumb. In The Second Encounter, **ZOOM** appears while you hold the sniper rifle, and **BOMB** (with how many you have) while you carry serious bombs.
- **A weapon wheel** on **NEXT WPN** and **PREV WPN**: every weapon with its HUD icon and its ammo, so you can pick the one you want. Slide to pick in one movement, or hold to open it and tap. A quick tap still switches to the next or previous weapon.
- **Tilt aiming (gyro):** aim by turning the phone, on top of dragging. It's **off** until you switch it on in MENU's hidden tray.
- **QUICK SAVE** and **QUICK LOAD** that need a short hold, so a stray touch can't save over your quick save or load an old one.
- **MENU's hidden tray** (hold **MENU**): tilt aiming's sensitivity and mode, an FPS counter, and the keyboard for the game's console.
- **The messages envelope** in the HUD's top row: tap it to mark your messages read, hold it to open NETRICSA.
- **A HUD that fits iPhone screens:** clear of the rounded corners, the notch or Dynamic Island and the home bar, with the ammo boxes at the bottom right gone. In The Second Encounter, the power-ups move to the top row and BOMB counts your bombs.
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

Exact positions shift a little to fit your screen, the camera cutout and the HUD. ZOOM and BOMB only show when you can use them, so never in The First Encounter, which also has no power-ups. Buttons are slightly see-through until you touch them, and a touch just beside a button still counts. While the game is paused, only **RESUME** (in the middle of the screen) and **MENU** show.

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
| **USE** | up and left of FIRE | Works switches. It never opens NETRICSA (that's the envelope), and in The Second Encounter it never works the sniper scope (that's ZOOM). |
| **JUMP** | above FIRE | Jumps. |
| **ZOOM** | right of FIRE, only while the sniper rifle is in your hands (The Second Encounter only) | Tap to look through the scope, tap again to stop. Hold it while scoped to zoom in further. Like Use on PC, it works a switch instead if there's one in front of you. |
| **BOMB** | right of JUMP, only while you carry serious bombs (The Second Encounter only) | Shows how many you have, under the word BOMB. Sets one off when you **lift** your finger on it. Dragging on it doesn't look, so a look swipe that starts on BOMB can't waste a bomb. |
| **NEXT WPN** and **PREV WPN** | top left, below your score | Tap: next or previous weapon. Slide or hold: the weapon wheel. See *The weapon wheel* below. |
| **QUICK SAVE** and **QUICK LOAD** | top right | Hold for about a third of a second. See *Quick save and quick load* below. |
| **MENU** | top right corner | Tap: the game's menu. Hold: the hidden tray. |
| **RESUME** | middle of the screen, only while paused | Tap to carry on. |

FIRE, CROUCH, USE, JUMP and ZOOM act as soon as you touch them. BOMB, MENU, RESUME and the tray's buttons act when you **lift** your finger, so if you touch one by mistake, slide off before you lift.

The touch buttons don't go through the game's key bindings, so they keep working whatever keys you bind.

#### The weapon wheel (NEXT WPN and PREV WPN)

Both buttons have three gestures, and both open the same wheel:

- **Quick tap:** lift within about a third of a second, without sliding. NEXT WPN switches to your next weapon and PREV WPN to the previous one, as you lift. In The Second Encounter, with the sniper scope on, NEXT WPN zooms out and PREV WPN zooms in instead, as on PC.
- **Slide** (the quickest way to pick): touch the button and slide your thumb away. The wheel opens **at once**. Keep sliding towards a weapon: a short slide in its direction is enough. If you can take it, its slice pops out. Its name shows in the middle, and, on iPhones with haptics, you feel a light tick. **Lift to take it.**
- **Hold:** touch and hold still for about a third of a second. A ring fills round the button, then the wheel opens and **stays open**. Lift, then **tap** a weapon to take it. (Or, without lifting, slide out to pick by sliding after all.)

Changing your mind:

- **While sliding:** lift in the **gap at the bottom** of the wheel (marked *cancel*), or back where you started. Lifting on a weapon you can't take also changes nothing. A slide too short to point at anything leaves the wheel open for tapping.
- **When it's open for tapping:** tap the middle, the gap, anywhere outside the wheel, a button, or the weapon you already hold, and the wheel closes with no change. Tapping a weapon you can't take does nothing and leaves the wheel open.

What the wheel shows:

- **One slice per weapon**, always in the same place, in the order NEXT WPN steps through them, clockwise from the bottom left. **The Second Encounter** has 14: Knife, Chainsaw, Colt, Two Colts, Shotgun, Double Shotgun, Tommygun, Minigun, Rocket Launcher, Grenade Launcher, Flamethrower, Sniper Rifle, Lasergun, Cannon. Its serious bomb isn't on the wheel: it has BOMB. **The First Encounter** has 11: Knife, Colt, Two Colts, Shotgun, Double Shotgun, Tommygun, Minigun, Rocket Launcher, Grenade Launcher, Lasergun, Cannon.
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
- **At 1.0x the view turns as far as the phone does.** The game's mouse settings don't change tilt aiming: use **SENS**. Very slow drifts are damped on purpose, so a phone held still doesn't creep. In The Second Encounter, the sniper scope's zoom slows it down, as it slows every turn.
- Tilt aiming pauses while the weapon wheel or MENU's tray is open. It's off in the menus, NETRICSA and the console, while the game is paused or loading, and while you're out of the app.
- On a device without a motion sensor, GYRO says **NO GYRO** and does nothing.

#### Messages and NETRICSA: the envelope

The HUD's messages box (an envelope with the number of unread messages) sits in the **HUD's top row, right of the high score**, instead of at the bottom right as on PC, which is under FIRE here. It blinks while you have unread messages.

- **Tap the envelope** to mark every message read, so it stops blinking. NETRICSA doesn't open. Your saves keep which messages are read.
- **Hold the envelope** until a ring fills round it (about half a second) to open **NETRICSA**. Inside NETRICSA, tap as you'd click.
- **In The First Encounter, NETRICSA also opens by itself** at the start of a level, with the level's briefing, as on PC. Tap **Exit**, at its top right, to get to the game.
- **With nothing unread**, the envelope stays, dim, with a **0**, so you can always hold it to open NETRICSA. A tap on it then does nothing.
- If your finger slides off the envelope, nothing happens.
- Until you've opened NETRICSA once, the game reminds you when a new message comes in: *Hold the envelope at the top to read the message!*
- **USE never opens NETRICSA**, however quickly you tap it twice.
- If you switch off the HUD's messages box, or the whole HUD, there's no envelope, and so no way into NETRICSA by touch.

#### The HUD

- **It fits rounded, notched screens:** the HUD, the game's messages, the clock and the stats stay clear of the rounded corners, the notch or Dynamic Island and the home bar. (In The Second Encounter, the sniper scope's view still fills the whole screen.)
- **No ammo boxes at the bottom right:** that row isn't drawn, because it would be under FIRE. Your current weapon and its ammo still show at the bottom middle, as on PC, and in The Second Encounter **BOMB** shows how many serious bombs you have.
- **Power-ups** (The Second Encounter only) show in the top row, between the score and the high score: the same icons, bars and running-out beep as on PC.
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

- **The First Encounter has had less testing than The Second Encounter.** It has been played on one iPhone, and tested on a computer with a PC copy of the game set out as on the phone and simulated touches. There the intro, the menus, a new game, moving, looking, FIRE, JUMP and CROUCH, the weapon wheel, quick save and quick load, the envelope and NETRICSA, tilt aiming, leaving the app and coming back, the second level and the demos all worked. If something goes wrong in Sam FE, please report it (see *Found a bug?*).
- **Single player only.** The touch controls only appear in single-player games. Co-op and multiplayer have no touch controls and haven't been tested.
- **No typing in the game's menus** (player names, save names). Typing works in the console.
- **NETRICSA by touch needs the envelope**, so keep the HUD's messages box on.
- **Leaving the app doesn't save your game**, only your settings.
- **Limited testing so far:** Sam SE and Sam FE have each been played on one iPhone so far. Not tried yet: iPads; older iOS versions (both apps are built for iOS 14 and newer); game controllers, hardware keyboards, mice and trackpads; game files from other editions (*Serious Sam Classics: Revolution*, the HD remakes, CD and non-English versions); PC saves on the phone, or phone saves on PC; restoring a backup of your saves; whether installing a newer version with your sideloading tool keeps your files.
- **The HUD on narrower iPhones:** with the HUD set larger than normal, or the legacy HUD, a layout check found that the messages count or a boss's health bar can sit under QUICK SAVE, and the armour icon under the notch or Dynamic Island. On the smallest iPhones (the size of the first iPhone SE), the messages count and the boss's health bar can sit under QUICK SAVE at the normal HUD size too. This hasn't been seen on a phone.

### Requirements

- An **iPhone on iOS 14 or newer.** The apps are also marked for iPad, but neither has ever been installed or tried on one.
- **Your own PC copy of the game**, for its game files. You'll need the computer it's installed on, to copy them to your iPhone.
  - For **Sam FE**, *Serious Sam: The First Encounter*: its six `.gro` files and its `Levels`, `Help` and `Demos` folders, listed under *Install*, about 380 MB in the copy this was tested with.
  - For **Sam SE**, *Serious Sam: The Second Encounter*: the eight `.gro` files listed under *Install* and the `Help` folder, about 410 MB in the copy this was tested with.
- A **sideloading tool or signing service** (something that installs apps from outside the App Store) that can install an app file (`.ipa`) you give it, for example Signulous. The `.ipa` files aren't signed for your iPhone, so they can't be installed without one.

### Install

1. Download the `.ipa` for your game, below: **`serioussam-ios.ipa`** for The First Encounter, or **`serioussamse-ios.ipa`** for The Second Encounter (*se* after *serioussam*, as in Sam SE). To play both games, download both and do each step for each app.
2. Install it with your sideloading tool or signing service, following that tool's own instructions (whether iOS asks you to trust a developer or to turn on Developer Mode depends on the tool). On your home screen the app is called **Sam FE** (The First Encounter) or **Sam SE** (The Second Encounter). Both have the same icon, so tell them apart by the name. Its version shows as 0.1 followed by a build number, even though this release is v0.2: that's expected.
3. **Open the app once.** With no game files yet, it shows a *Fatal Error* box saying *Game data not found*. Tap OK and the app closes. That's expected: by then the app has made its folder for your files, *On My iPhone > Sam FE* or *On My iPhone > Sam SE* in the Files app.
4. On your computer, open the folder the game is installed in, and find:
   - **for Sam FE (The First Encounter):** all the `.gro` files, `1_00c.gro`, `1_00c_scripts.gro`, `1_00c_Logo.gro`, `1_00_ExtraTools.gro`, `1_00_music.gro` and `1_04_patch.gro`, and the `Levels`, `Help` and `Demos` folders. **Don't leave out `Levels`:** The First Encounter's levels are in it, not in the `.gro` files.
   - **for Sam SE (The Second Encounter):** all the `.gro` files, `SE1_00.gro`, `SE1_00_Extra.gro`, `SE1_00_ExtraTools.gro`, `SE1_00_Levels.gro`, `SE1_00_Logo.gro`, `SE1_00_Music.gro`, `1_04_patch.gro` and `1_07_tools.gro`, the `Help` folder, and a `Levels` folder if your game folder has one.

   You don't need `Bin` or any of the other folders. Not sure where the game is installed? Search your computer for `1_00_music.gro` (The First Encounter) or `SE1_00_Levels.gro` (The Second Encounter): the folder it's in is the one.
5. Copy them into the Files app's **On My iPhone > Sam FE** or **On My iPhone > Sam SE**, the app for that game, **directly** into that folder (the `.gro` files and the folders as they are: not inside another folder, and not as a `.zip`), with their names unchanged. Use whatever way you like to get files into the Files app, for example iCloud Drive: copy them into iCloud Drive on your computer, then move them into the app's folder in the Files app. `SE1_10b.gro` (an engine file both apps add, not a Second Encounter file), `ModEXT.txt` and two `.log` files are already there: the app makes them itself, so leave them.
6. **Open the app again.** If the intro plays, tap to get to the main menu.

**If the game files are missing:** each app checks for one file directly in its folder: Sam FE for `1_00_music.gro`, Sam SE for `SE1_00_Levels.gro`. If it can't find it, it shows the *Fatal Error* box, *Game data not found*, naming the missing file, and closes when you tap OK. Check that the files are directly in the app's folder, *On My iPhone > Sam FE* or *Sam SE*, not in a folder inside it and not zipped, with their names unchanged, then open the app again. Each app takes only its own game: The Second Encounter's files won't start Sam FE, and The First Encounter's won't start Sam SE. The app checks only for that one file, so also make sure everything from step 4 is there.

**If Sam FE starts but no intro plays,** and choosing a difficulty under *NEW GAME* leaves you in the menu (for a few seconds, *Cannot start game* and a *Cannot open file* line naming `Levels/01_Hatshepsut.wld` show at the top of the screen), the `Levels` folder is missing: copy it into Sam FE too.

**Your saves** are in the Files app, in the app's own folder: *On My iPhone > Sam FE* or *Sam SE*, then *SaveGame > Player0*, with quick saves in its `Quick` folder. Your player profile is in the app's *Players* folder. As two separate apps, Sam FE and Sam SE each keep their own files, saves and settings.

- **Back up** now and then by copying `SaveGame` and `Players` somewhere safe (for example iCloud Drive), and always before you delete or reinstall an app: deleting an app deletes its folder, game files and saves included.
- The SENS, GYRO and FPS settings are kept by iOS, not in the app's folder.
- **If something goes wrong:** `SeriousSam.log` and `Output.log`, directly in the app's folder (next to the `.gro` files), say what the game was doing. Copy them out before you open the app again, because each start empties them. **Found a bug?** Report it at https://github.com/sithewok13-dev/SeriousSamClassic/issues with both log files attached, and say which game, which iPhone and iOS version you have and what you were doing. It's an iOS build of its own, so please report its problems there, not to the upstream SeriousSamClassic project.

**Download:** under *Assets* below: `serioussam-ios.ipa` is The First Encounter (Sam FE), and `serioussamse-ios.ipa` is The Second Encounter (Sam SE). The *iOS latest build* prerelease, also on the Releases page, is rebuilt automatically after every code change, before anyone has tried it: use this release.

---

Unofficial builds. Serious Sam: The First Encounter, Serious Sam: The Second Encounter and Serious Engine 1 are by Croteam, who released the engine's source code (Serious Engine 1.10) under the GNU GPL v2. These builds are based on [tx00100xt/SeriousSamClassic](https://github.com/tx00100xt/SeriousSamClassic). They are not an official Croteam release, and they are not affiliated with or endorsed by Croteam or Devolver Digital. No game files are included.

These apps are free software under the GNU GPL v2 (https://github.com/sithewok13-dev/SeriousSamClassic/blob/ios/LICENSE). Their source code, iOS changes included, is the `ios` branch: https://github.com/sithewok13-dev/SeriousSamClassic/tree/ios (this release is the tag `ios-v0.2`: https://github.com/sithewok13-dev/SeriousSamClassic/tree/ios-v0.2).

The apps also include libraries under their own licences: SDL2 (zlib licence, https://github.com/libsdl-org/SDL/blob/release-2.30.8/LICENSE.txt), gl4es (MIT licence, https://github.com/ptitSeb/gl4es/blob/ec16bedd8819c475326f4f1a3063772c6d986e06/LICENSE), which turns the engine's OpenGL into the iPhone's OpenGL ES, and libogg and libvorbis by the Xiph.Org Foundation (BSD-style licence, https://github.com/sithewok13-dev/SeriousSamClassic/blob/ios/SamTSE/Sources/External/libvorbis/COPYING and https://github.com/sithewok13-dev/SeriousSamClassic/blob/ios/SamTSE/Sources/External/libogg/COPYING), which decode the music.

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
