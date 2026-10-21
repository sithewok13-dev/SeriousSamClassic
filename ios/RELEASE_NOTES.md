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

**Serious Sam Classic for iOS v0.3**: unofficial iPhone builds of *Serious Sam: The First Encounter* and *Serious Sam: The Second Encounter*, running on Croteam's open-source Serious Engine 1 (by way of [tx00100xt/SeriousSamClassic](https://github.com/tx00100xt/SeriousSamClassic)), with on-screen touch controls made for them.

**You need your own copy of the game; no game files are included.** You copy the game's files from your PC copy of The First Encounter or The Second Encounter onto your iPhone (see *Install*).

**Two apps, one for each game:** **Sam FE** (`serioussam-ios.ipa`) plays The First Encounter, and **Sam SE** (`serioussamse-ios.ipa`) plays The Second Encounter. Install the one for the game you have, or both. If something goes wrong in either, please report it (see *Found a bug?*).

**New here?** *Known limitations*, *Requirements* and *Install* are near the bottom of this page, just above the download.

### What's in ios-v0.3

**New since ios-v0.2**, in both apps, Sam FE and Sam SE:

- **CAMERA:** a camera button in the top row. Tap it for a photo, hold it for a **selfie** with the enemies around you posing, slide it sideways for a **burst**, slide it down for **Action Freeze** (stop the game and move the camera round it) or up for a **cinematic burst** (five photos as the camera sweeps round the action). Photos go to your Photos app. See *The camera* below.
- **Network games:** the games' own multiplayer now works on iPhone, with the touch controls. Play with friends on the **same Wi-Fi** (host a game, and the others find it with *SEARCH LAN* or join by its address), or join a server on the internet. See *Network games* below.
- **Typing in the menus:** the iPhone keyboard now comes up for the game's text boxes, such as a player's name, a save's name or a server's address.
- **A cheat, `sithewok`:** god mode, every weapon with ammo that never runs out, flying, walking through walls, being caught when you fall into a pit, and a level picker. Switch it on from MENU's tray, or type `sithewok` in the console. In a network game it only works if the host allows it. See *The cheat* below.

What hasn't changed: moving, looking, the weapon wheel, quick save and quick load, tilt aiming, the envelope and the HUD all work as in ios-v0.2. MENU's tray has more buttons now (CAMERA, CHEAT and, while the cheat is on, LEVEL).

**This release has had less testing than ios-v0.2.** Everything new in it was tested on a computer, with the real game files and simulated touches, and some of it on an iPhone, but not all of it on an iPhone yet: see *Known limitations*.

---

### How to play: every control explained

The touch controls appear while you're playing, in a single-player or a network game, and hide in the menus, NETRICSA, the intro, demos and while a level loads (there you just tap, as you'd click with a mouse). The game runs in landscape, either way round.

Where everything is (on a phone, turn it sideways to see the whole picture):

```
 SCORE   power-ups  CHEAT CAMERA  HIGH SCORE  envelope   QUICK  QUICK  MENU
 NEXT  PREV                                              SAVE   LOAD
 WPN   WPN     [SENS] [GYRO] [FPS] [camera] [CHEAT] [LEVEL] [keyboard]
                              (MENU's tray, while it's open)

                                                                    BOMB
                                                            JUMP
                                                   USE
     ( o )  move stick: appears                                     ZOOM
            where your left thumb lands      CROUCH         FIRE
                         [weapon and ammo]
```

Exact positions shift a little to fit your screen, the camera cutout and the HUD. CAMERA sits in the top row as near the middle as the HUD allows, with CHEAT (only once you've switched the cheat on) beside it. ZOOM and BOMB only show when you can use them, so never in The First Encounter, which also has no power-ups. Buttons are slightly see-through until you touch them, and a touch just beside a button still counts. While the game is paused, only **RESUME** (in the middle of the screen) and **MENU** show.

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
| **CAMERA** | top row, near the middle | Tap: a photo. Hold: a selfie. Slide: a burst, Action Freeze or the cinematic burst. See *The camera* below. |
| **CHEAT** | beside CAMERA, only once you've switched the cheat on | Hold: the cheat off or on. A tap does nothing. See *The cheat* below. |
| **QUICK SAVE** and **QUICK LOAD** | top right | Hold for about a third of a second. See *Quick save and quick load* below. In a network game, only the host of a cooperative game has them. |
| **MENU** | top right corner | Tap: the game's menu. Hold: the hidden tray. |
| **RESUME** | middle of the screen, only while paused | Tap to carry on. |

FIRE, CROUCH, USE, JUMP and ZOOM act as soon as you touch them. BOMB, MENU, RESUME and most of the tray's buttons act when you **lift** your finger, so if you touch one by mistake, slide off before you lift.

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

- **The game holds still** (in single player), so take your time. *Paused* doesn't show, the game's sounds stop, and the music keeps playing. Other touches and tilt aiming are ignored until the wheel closes.
- The wheel doesn't open while you're dead, during a cutscene or while the game is moving you, and it closes by itself, picking nothing, if one of those happens. It also closes when the menu, the console, NETRICSA or a quick load comes up, when the game pauses, and when you leave the app.

#### Quick save and quick load: why the short hold

**QUICK SAVE** makes a quick save and **QUICK LOAD** loads your latest one. Both need you to **hold** the button for about a **third of a second**: a ring fills round it, and when it's full the game saves or loads, once, with your finger still down.

**Why the hold?** So a stray touch can't save over your quick save, or throw away your progress by loading an old one. These buttons sit at the top of the screen next to MENU, and a quick brush past them does nothing.

- **To cancel**, lift or slide off before the ring fills. Once you've slid off it won't go off, even if you slide back on.
- **To do it again**, lift, then touch and hold again.
- **No quick save yet?** Then QUICK LOAD does nothing, and *No quicksave yet* shows for a moment at the top of the screen.
- **Normal saves:** tap MENU and use the game's own save and load screens. To save, tap `<save a new one>`: the iPhone keyboard comes up with the name the game suggests (the level and the date). Change it if you like, then tap Return.

#### MENU and its hidden tray

**Tap MENU** for the game's menu (it opens when you lift your finger). **Hold MENU** until its ring fills (about half a second) and a small tray opens just under it instead, with these buttons, from left to right:

| Tray button | What it does |
| --- | --- |
| **SENS** | Tilt aiming's sensitivity: **1.0x**, **1.5x** (the default), **2.0x** or **3.0x**. At 1.0x the view turns as far as the phone does. Dimmed while GYRO is off. |
| **GYRO** | Tilt aiming: **OFF** (the default), **TOUCH** or **ALWAYS**. Edged in yellow while tilt aiming is on. See *Tilt aiming* below. |
| **FPS** | Shows or hides a frame-rate counter next to QUICK SAVE. Edged in yellow while it's on. |
| **Camera** (the camera symbol) | Shows or hides CAMERA in the top row. Edged in yellow while CAMERA shows. Hold it for CAMERA's options (see *The camera*). |
| **CHEAT** | Switches the cheat on and shows the CHEAT button, or, tapped again, leaves cheat mode. Edged in yellow while the CHEAT button shows. See *The cheat*. |
| **LEVEL** | Only while the cheat is on, in single player: hold it to pick a level. See *The cheat*. |
| **Keyboard** (the keyboard symbol) | Opens the game's console with the iPhone keyboard, for console commands. |

- SENS and GYRO show their setting on the button (for example *SENS 1.5x*, *GYRO OFF*).
- Either keep your thumb down, slide it onto a tray button and lift, or lift first and then tap one.
- Each tap on **SENS** or **GYRO** moves on to the next setting, and the tray stays open so you can tap again. The tray closes after **FPS**, the camera symbol, **CHEAT** or the keyboard, or when you touch anywhere else. That touch still counts: touching FIRE closes the tray and fires. Touching MENU again only closes it.
- If you slide off MENU while holding it, nothing happens.
- The app **remembers SENS, GYRO, FPS, CAMERA (and its options) and whether CHEAT shows** for next time.
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

#### The camera: photos, selfies, bursts and Action Freeze

**CAMERA** (the camera symbol) sits in the top row, near the middle. It's there from the start; to hide it (or show it again), hold **MENU** and tap the **camera symbol** in the tray. The first time you use it, iOS asks whether the app may **add photos** to your library: say yes, and the photos go straight into your Photos app. The game holds still while iOS asks. The app can only add photos; it can't see the ones already in your library.

What CAMERA does depends on how you touch it:

| Gesture | What it does |
| --- | --- |
| **Tap** | A photo of the game. |
| **Hold still** (half a second, a ring fills) | A selfie (1, 3 or 5 photos). |
| **Slide off sideways** | A burst: a photo every fifth of a second while your finger stays down. |
| **Slide down** (a long slide) | Action Freeze: stop the game and move the camera round it. |
| **Slide up** (towards the top edge) | The cinematic burst: five photos as the camera sweeps round the action. |

With **FREEZE** switched off (in CAMERA's options, below), a slide in any direction is a burst.

**Selfies:** hold CAMERA still for half a second.

- The whole game freezes, every enemy and boss included, and the HUD and touch buttons hide.
- The view switches to the phone, held out at about arm's length and facing Sam. Up to **48 of the enemies nearest you**, in sight, turn to the camera and strike a pose: each one a moment from its own animations, mid-attack, roaring, standing about, flinching or mid-stride. Some turn three-quarters to the camera, and now and then the whole crowd strikes the same kind of pose. In a tight crowd they stand calmly, so they don't swing their claws through each other.
- **Sam** turns to the camera too: an arm up as if holding the phone, showing off his gun, both arms out, or looking about. The camera angle changes from shot to shot: sometimes a little higher or lower, sometimes slightly tilted.
- **Now and then something unexpected happens:** everyone stares at Sam, one enemy hasn't noticed the photo, or a passer-by from further away photobombs and everyone stares at them.
- **1, 3 or 5 photos:** a selfie takes **3** unless you change it with **SELFIES** in CAMERA's options. Everyone poses afresh for each one, and the game stays frozen the whole time.
- **Sam is always the nearest one in the photo:** enemies between the camera and him, or standing over him, are left out of it, and so are shots and blasts in front of someone's face. **The flash** lights Sam and the faces near the camera, however the level is lit behind them.
- After the flash and the shutter, the photo stays on screen for a moment. Then everyone goes back to exactly what they were doing, and the game carries on. A selfie changes nothing in your game.
- **Nobody nearby?** It's a selfie of Sam alone.
- Selfies are always clean photos (*... selfie.png*), whatever PHOTO is set to.
- **When it can't:** if there's no room to hold the camera out (right up against a wall), or the game is showing a cutscene or the sniper scope, or you're dead, it says *Can't take a selfie here*. If the last photos are still being saved, it says *Still saving the last photo*: try again in a moment. In a network game it says *Selfies are for single player*.

**Photos and bursts:**

- **Tap CAMERA:** a white flash, the camera's shutter sound, and the photo. A line at the top of the screen says when it's saved (*1 photo saved*).
- **Burst:** touch CAMERA and slide your finger off it sideways (a short slide is enough). The app takes a photo every fifth of a second for as long as your finger stays down, up to 10, with a quick tick for each and a counter by the button. Lift your finger to stop. Burst photos are always clean ones, without the HUD.
- Photos and bursts work in network games too.

**Action Freeze:** touch CAMERA and slide your finger **down**, further than for a burst.

- The game stops exactly where it is: rockets, explosions, flying debris and every enemy mid-move. The buttons hide, apart from CAMERA, and an **X** appears at the top right.
- **One finger** turns the camera round what it's looking at. **Two fingers** move it, and **pinch** to zoom in or out.
- The camera stays out of walls and closed doors. If it can't go somewhere, it stops. Close to a wall it moves in a little, and glides back out when there's room.
- **Tap CAMERA** to take a clean photo, as many as you like. **Tap the X** to go back to the game, which carries on from exactly the same moment.
- If it can't freeze (a cutscene, the sniper scope, while dead), it says *Can't freeze here*. In a network game it says *Action Freeze is for single player*.

**The cinematic burst:** touch CAMERA and slide your finger **up**. Reaching near the top edge of the screen is enough.

- The game freezes for a moment and the camera takes **five photos** as it sweeps round the action, then the game carries on by itself.
- The first photo is exactly what you saw. The other four go round the most interesting thing in front of you: an enemy you're fighting, a rocket in flight or an explosion. With a boss or an enemy close by, Sam and it are both in the shots, seen from the side. With nothing around, it goes round Sam.
- The sweep picks the side with the most room, so the camera doesn't end up inside a wall.

**CAMERA's options:** open the tray (hold MENU), then touch and hold the **camera symbol in the tray** until its ring fills. A row opens under the tray with three buttons:

- **PHOTO:** what a tap takes. Tap PHOTO for its three tick boxes: **CLEAN** (just the game, no HUD or buttons: ticked unless you change it), **HUD** (the game with its HUD) and **HUD+BTNS** (with the touch buttons too, as you see the screen). At least one stays ticked. If you tick more than one, each tap of CAMERA takes one photo of each, all of the same moment.
- **SELFIES:** how many photos a selfie takes: **1**, **3** (the default) or **5**. Each tap goes on to the next.
- **FREEZE:** **ON** (the default) or **OFF**. Off, sliding CAMERA down or up is just a burst.
- Touch anywhere else to close the row and the tray.

**Where the photos go:**

- Photos are full-screen PNGs, named after the app and the time, for example *Sam SE 2026-10-16 14.05.09 clean.png* (a burst's are numbered: *... burst 01.png*). In The First Encounter they start with *Sam FE*.
- **If Photos access is off** (you said no, or turned it off in *Settings*), the photos go to the Files app instead, in *Sam FE > Screenshots* or *Sam SE > Screenshots*, and the message says so. To use the Photos app again: *Settings > Privacy & Security > Photos*, then the app, then *Add Photos Only*.

#### Network games

The games' own multiplayer (cooperative, scorematch and fragmatch, as on PC) works on iPhone, with the same touch controls. Tap **MENU**, then **NETWORK**:

- **To host a game:** *START SERVER*, choose the game type, the level and the rest, then *START*. For a few seconds the top of the screen shows where the others can join, for example *Others join at 192.168.1.23 (or SEARCH LAN)*. Keep the app open while the others play: if you switch to another app, iOS may stop Sam, and the game with it.
- **To join a game on the same Wi-Fi:** *JOIN GAME*, then *SEARCH LAN*. The search takes a few seconds; then tap a game in the list to join it (it joins as you lift your finger, so you can drag the list to scroll). Or tap *SPECIFY SERVER* and type the host's address.
- **To join a server on the internet:** *JOIN GAME*, then *SEARCH INTERNET*, or *SPECIFY SERVER* with the server's address.
- **The first time**, iOS asks whether the app may find and connect to devices on your **local network**. Say yes, or neither hosting nor *SEARCH LAN* can work. To change it later: *Settings > Privacy & Security > Local Network*.
- **Every player needs their own copy of the game**, and everyone plays the same one: Sam FE with Sam FE, Sam SE with Sam SE.
- The connection settings are chosen for you (a faster one on the same Wi-Fi, a steadier one over the internet), so the game doesn't ask.

What's different in a network game:

- **QUICK SAVE and QUICK LOAD** only show for the host of a cooperative game: in the other games, and for the players who joined, there's nothing to save.
- **Nothing holds the game still:** the weapon wheel and MENU's tray open as usual, but the game, and everyone in it, carries on meanwhile.
- **Selfies and Action Freeze** are single player only. Photos and bursts work.
- **The cheat** only works if the host allows it (see *The cheat*). The level picker is single player only.

#### The cheat (sithewok)

A cheat for when you just want to enjoy the levels. It gives you, all at once: **god mode** (nothing hurts you), **every weapon with ammo that never runs out**, full health and armour (and, in The Second Encounter, serious bombs), and falls that never hurt. **Fall into a pit and you're caught**: put back where you last stood on solid ground, with a soft blue flash. A fall that goes on for over 3 seconds is caught the same way. It stays on through new levels and loaded games, and gives you everything again at each new level.

**Switching it on:**

- Hold **MENU** and tap **CHEAT** in the tray. A **CHEAT** button (a bomb with a lit fuse) appears in the top row, next to CAMERA, the cheat comes on, and Sam says one of his lines (*"Let's get serious!"* and others in The First Encounter; *"Sam I am!"* or *"Yeehaw!"* in The Second Encounter, from your own game files).
- Or open the console (hold MENU, tap the keyboard button) and type **`sithewok`**, then Return. Typing it again switches it off.

**While it's on:**

- **Hold CHEAT** in the top row for half a second (a ring fills) to switch the cheat **off** (the bomb turns grey) or back **on** (gold). A tap on it does nothing, so you can't switch it by accident.
- **Hold JUMP still** for half a second: **fly.** Look where you want to go and move; JUMP rises, CROUCH sinks. **Tap JUMP twice quickly** to land.
- **Hold USE still** for half a second: **walk through walls** (noclip). Hold it again to stop.
- Small red labels, *FLY* and *NOCLIP*, under JUMP and USE remind you. Quick presses still jump and use as always, and **CROUCH only ever crouches**.
- Flying and walking through walls stop at each new level.
- What the cheat gave you is kept when you switch it off.

**The level picker: LEVEL**, in MENU's tray, right after CHEAT (only while the cheat is on, in single player):

- **Hold LEVEL.** After half a second it shows **1**, then counts on, **2, 3, ...**, one every 0.4 seconds, with a tick and *Level 2 of 15* at the top of the screen. After the last level it starts again at 1.
- **Lift your finger on it** to go to that level: it starts as a new game at the same difficulty, with the weapon you had in your hands.
- **To cancel**, slide off LEVEL before you lift, or close the tray. A quick tap only says *Hold LEVEL to count levels*.
- The First Encounter has 15 levels to pick from, The Second Encounter 13.

**Leaving cheat mode:** hold MENU and tap **CHEAT** in the tray again: the cheat goes off and its button goes away. The app remembers whether the CHEAT button shows, but the cheat itself is **off each time you open the app**.

**In a network game**, the cheat only works if the host set **Allow cheats** to *Yes* on *START SERVER* (it's *No* unless they do). Then each player can switch it on for themselves. Otherwise CHEAT says *This game doesn't allow cheats (the host's ALLOW CHEATS)*.

The game's own console cheats work as before.

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
- **Typing in the menus:** tap a text box (a player's name, a save's name, a server's address) and the iPhone keyboard comes up, with the screen moved up so the box stays above it. Tap Return to accept.
- **Customize Controls:** when the game asks you to press a key to bind, a tap ends the wait and keeps the old binding (touches can't be bound). You don't need to change bindings: the touch buttons don't use them.
- **Leaving the app** (going to the home screen or another app): a single-player game pauses and your settings are saved. **Your game isn't saved**, and iOS can close an app that's in the background, so quick save first if you might be away a while. When you come back, the game is paused with **RESUME** and **MENU** on screen.
- **The console:** hold MENU and tap the keyboard button. The console opens with the iPhone keyboard. Tap MENU to close it.

#### Small print

- **Weapon wheel:** if iOS cancels your touch while the wheel is open and the game stays on screen, the wheel stays open: tap a weapon, or tap anywhere else to close it.
- **Quick save and quick load:** two fingers on one button still save or load only once. With both buttons held, only the one whose ring fills first goes off, never both (if both fill at the same moment, it saves).
- **MENU's tray:** anywhere on its dark backing counts as the nearest tray button.
- **Tilt aiming:** turning left and right works however far back you tip the phone, even lying flat. It pauses for a moment after you turn the phone round to the other landscape side.

### Known limitations

- **New in this release, and not all of it tried on an iPhone yet:** the camera has been used on an iPhone (and its selfies improved since, from photos taken there), but the network games, the cheat and the LEVEL button have so far been tested only on a computer, with the real game files and simulated touches. If something goes wrong, please report it (see *Found a bug?*).
- **Network games:** tested on a computer, with a game hosted and joined on the same network, *SEARCH LAN*, joining by address, and a dedicated server, in both games. Not tried yet: two iPhones playing together, an iPhone with a PC, and the internet server list (*SEARCH INTERNET*). iOS doesn't let apps installed this way send a network-wide broadcast, so *SEARCH LAN* asks each address on your Wi-Fi in turn instead, which takes a few seconds and finds games on the usual ports only (25600 to 25604).
- **The First Encounter has had less testing than The Second Encounter.** If something goes wrong in Sam FE, please report it.
- **NETRICSA by touch needs the envelope**, so keep the HUD's messages box on.
- **Leaving the app doesn't save your game**, only your settings.
- **Limited testing so far:** Sam SE and Sam FE have each been played on one iPhone so far. Not tried yet: iPads; older iOS versions (both apps are built for iOS 15 and newer); game controllers, hardware keyboards, mice and trackpads; game files from other editions (*Serious Sam Classics: Revolution*, the HD remakes, CD and non-English versions); PC saves on the phone, or phone saves on PC; restoring a backup of your saves; whether installing a newer version with your sideloading tool keeps your files.
- **The HUD on narrower iPhones:** with the HUD set larger than normal, or the legacy HUD, a layout check found that the messages count or a boss's health bar can sit under QUICK SAVE, and the armour icon under the notch or Dynamic Island. On the smallest iPhones (the size of the first iPhone SE), the messages count and the boss's health bar can sit under QUICK SAVE at the normal HUD size too, and the open tray covers the CHEAT button. This hasn't been seen on a phone.

### Requirements

- An **iPhone on iOS 15 or newer.** The apps are also marked for iPad, but neither has ever been installed or tried on one.
- **Your own PC copy of the game**, for its game files. You'll need the computer it's installed on, to copy them to your iPhone.
  - For **Sam FE**, *Serious Sam: The First Encounter*: its six `.gro` files and its `Levels`, `Help` and `Demos` folders, listed under *Install*, about 380 MB in the copy this was tested with.
  - For **Sam SE**, *Serious Sam: The Second Encounter*: the eight `.gro` files listed under *Install* and the `Help` folder, about 410 MB in the copy this was tested with.
- A **sideloading tool or signing service** (something that installs apps from outside the App Store) that can install an app file (`.ipa`) you give it, for example Signulous. The `.ipa` files aren't signed for your iPhone, so they can't be installed without one.

### Install

1. Download the `.ipa` for your game, below: **`serioussam-ios.ipa`** for The First Encounter, or **`serioussamse-ios.ipa`** for The Second Encounter (*se* after *serioussam*, as in Sam SE). To play both games, download both and do each step for each app.
2. Install it with your sideloading tool or signing service, following that tool's own instructions (whether iOS asks you to trust a developer or to turn on Developer Mode depends on the tool). On your home screen the app is called **Sam FE** (The First Encounter) or **Sam SE** (The Second Encounter). Both have the same icon, so tell them apart by the name. Its version shows as 0.1 followed by a build number, even though this release is v0.3: that's expected.
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
- The SENS, GYRO, FPS, CAMERA and CHEAT-button settings are kept by iOS, not in the app's folder. Photos go to your Photos app (or, without Photos access, to the app's *Screenshots* folder).
- **If something goes wrong:** `SeriousSam.log` and `Output.log`, directly in the app's folder (next to the `.gro` files), say what the game was doing. Copy them out before you open the app again, because each start empties them. **Found a bug?** Report it at https://github.com/sithewok13-dev/SeriousSamClassic/issues with both log files attached, and say which game, which iPhone and iOS version you have and what you were doing. It's an iOS build of its own, so please report its problems there, not to the upstream SeriousSamClassic project.

**Download:** under *Assets* below: `serioussam-ios.ipa` is The First Encounter (Sam FE), and `serioussamse-ios.ipa` is The Second Encounter (Sam SE). The *iOS latest build* prerelease, also on the Releases page, is rebuilt automatically after every code change, before anyone has tried it: use this release.

---

Unofficial builds. Serious Sam: The First Encounter, Serious Sam: The Second Encounter and Serious Engine 1 are by Croteam, who released the engine's source code (Serious Engine 1.10) under the GNU GPL v2. These builds are based on [tx00100xt/SeriousSamClassic](https://github.com/tx00100xt/SeriousSamClassic). They are not an official Croteam release, and they are not affiliated with or endorsed by Croteam or Devolver Digital. No game files are included.

These apps are free software under the GNU GPL v2 (https://github.com/sithewok13-dev/SeriousSamClassic/blob/ios/LICENSE). Their source code, iOS changes included, is the `ios` branch: https://github.com/sithewok13-dev/SeriousSamClassic/tree/ios (this release is the tag `ios-v0.3`: https://github.com/sithewok13-dev/SeriousSamClassic/tree/ios-v0.3).

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
