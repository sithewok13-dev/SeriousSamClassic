/* On-screen touch controls for iOS. See IOSTouch.h.
   Built with ARC. The overlay lives for the whole process.

   Everything up to the overlay view is plain C: the buttons and their
   layout, the state shared with the game's thread, and what each touch does
   (the stick, looking, the buttons, the QUICK SAVE, QUICK LOAD and MENU
   holds, MENU's tray, the unread messages box's tap and hold, the FPS
   count, tilt aiming, NEXT WPN's and PREV WPN's taps, slides and holds and
   the weapon wheel they open: its slices, what it picks, its layout and its
   icons' tints). The view below only hands UIKit's touches and
   CoreMotion's samples to it and shows its state, so the Linux test drives
   this very code. */

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreMotion/CoreMotion.h>
#include <os/lock.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "SDL.h"
#include "SDL_syswm.h"
#include "IOSTouch.h"

// Look speed: mouse counts per point of finger travel. At the game's default
// mouse settings a count turns the view 0.25 degrees, so this turns it as far
// per point as the Jedi Knight port does (0.64 degrees across, 0.39 up/down).
#define IOSTOUCH_LOOK_SCALE_X 2.56f
#define IOSTOUCH_LOOK_SCALE_Y 1.56f
// Stick: radius in points; it appears wherever the left thumb lands in the
// left IOSTOUCH_STICK_ZONE of the screen, and only while that thumb is down.
// Pushed past IOSTOUCH_STICK_DEADZONE of the radius it starts moving, and by
// IOSTOUCH_STICK_FULL it moves at full speed (below about half speed the
// player walks, and won't step off ledges). Full speed comes early because
// Sam is played running, as with the keyboard on PC.
#define IOSTOUCH_STICK_ZONE 0.42f
#define IOSTOUCH_STICK_RADIUS 60.0f
#define IOSTOUCH_STICK_DEADZONE 0.15f
#define IOSTOUCH_STICK_FULL 0.30f
// Buttons show at this opacity while untouched, so they hide less of the game;
// a touched one shows at full strength
#define IOSTOUCH_IDLE_ALPHA 0.65
// Edge-to-edge gap between the buttons around FIRE (the arc, ZOOM and BOMB)
#define IOSTOUCH_CLUSTER_GAP 30.0
// QUICK SAVE and QUICK LOAD have to be held this long, so a stray tap can't
// save over the quicksave (the one QUICK LOAD loads) or throw away progress
#define IOSTOUCH_QUICKSAVE_HOLD 0.3
#define IOSTOUCH_QUICKLOAD_HOLD 0.3
// NEXT WPN and PREV WPN each take three gestures (as Jedi Knight's FORCE
// WHEEL and NEXT WPN). A quick tap (lifted sooner than IOSTOUCH_WHEEL_HOLD by
// the touch's own clock, never IOSTOUCH_WHEEL_OPEN_SLIDE from where it went
// down) is the next / previous weapon, as it lifts. Sliding that far opens
// the weapon wheel at once, to slide to a slice; held still for
// IOSTOUCH_WHEEL_HOLD (known as QUICK SAVE's hold is) it opens to tap one.
// Sliding to pick is measured from where the thumb went down: it points
// nowhere until IOSTOUCH_WHEEL_DEAD away, the point it is measured from
// trails at most IOSTOUCH_WHEEL_LEASH behind the thumb, and a slice stays
// picked until the thumb points IOSTOUCH_WHEEL_HYST degrees past its edge; on
// the wheel itself the slice under the thumb is picked. The wheel's outer
// radius is at most IOSTOUCH_WHEEL_R1_MAX, its hole IOSTOUCH_WHEEL_R0_FRAC of
// that; the slice pointed at pops out IOSTOUCH_WHEEL_POP. The name in the
// middle keeps IOSTOUCH_WHEEL_NEEDLE_CLEAR inside the hole's edge, clear of
// the needle that shows which way the thumb points.
#define IOSTOUCH_WHEEL_OPEN_SLIDE 10.0
#define IOSTOUCH_WHEEL_HOLD IOSTOUCH_QUICKSAVE_HOLD
#define IOSTOUCH_WHEEL_DEAD 14.0
#define IOSTOUCH_WHEEL_LEASH 60.0
#define IOSTOUCH_WHEEL_HYST 4.0
#define IOSTOUCH_WHEEL_POP 10.0
#define IOSTOUCH_WHEEL_R1_MAX 168.0
#define IOSTOUCH_WHEEL_R0_FRAC 0.37
#define IOSTOUCH_WHEEL_NEEDLE_CLEAR 12.0
#define IOSTOUCH_WHEEL_CANCEL (-2) // the "slice" of the gap at the bottom
// MENU held this long opens its tray (tilt aiming's sensitivity and mode,
// FPS, the keyboard); a tap opens the menu as it lifts. The tray's buttons
// are IOSTOUCH_TRAY_STEP apart in a row.
#define IOSTOUCH_MENU_HOLD 0.45
#define IOSTOUCH_TRAY_STEP 50.0
// The HUD's messages box held this long opens NETRICSA; a tap marks
// every message read as it lifts. As long as MENU's hold, with the same ring
// (both open something; QUICK SAVE's and QUICK LOAD's shorter holds only
// guard against a stray tap). It is timed as QUICK SAVE's, though: NETRICSA
// opens only once the finger is known to have stayed on (IOSTouch_TickHolds),
// so a tap whose lift arrives late, after a slow frame, still only marks the
// messages read -- NETRICSA opening by accident is what this is for -- and
// its ring fills to that time too. A touch this far from the box is still
// on it.
#define IOSTOUCH_MESSAGES_HOLD IOSTOUCH_MENU_HOLD
#define IOSTOUCH_MESSAGES_REACH 6.0
// The FPS readout: its size in points, and how long it counts frames for
// before it shows a new number
#define IOSTOUCH_FPS_W 54.0
#define IOSTOUCH_FPS_H 18.0
#define IOSTOUCH_FPS_PERIOD 0.5
// A tap too quick for any game tick to see is reported for this many ticks,
// then released for one
#define IOSTOUCH_PULSE_READS 2
// The HUD's frame (IOSTouch_GetHudFrame) keeps its corners this far inside the
// screen's rounded corners
#define IOSTOUCH_HUD_CORNER_GAP 2.0
// Tilt aiming (see IOSTouch_GyroFrame), as in the Jedi Knight port.
// CoreMotion's device motion gives the rotation rate with the gyro's bias
// already taken out, IOSTOUCH_GYRO_HZ times a second. Turning left and right
// is measured about the way up (against gravity), so it works the same
// however far back the phone is tipped ("player space": what the screen's
// yaw and roll axes turn about up together -- made up by as much as
// IOSTOUCH_GYRO_YAW_RELAX times for a phone held rolled a little to one
// side, but never more than the two turn in all). Where up says nothing
// about which way the player's head is -- the screen facing down at a player
// lying under it, or rolled over on its side -- it is about the screen's own
// up axis instead ("local space"). Tilting is about the screen's own
// side-to-side axis. Under IOSTOUCH_GYRO_SMOOTH deg/s the motion is averaged
// over the last IOSTOUCH_GYRO_SMOOTH_N samples (all of it under half that),
// and under IOSTOUCH_GYRO_SOFT deg/s it is scaled down, to nothing at rest,
// so a phone held still doesn't creep. A gap between two samples longer than
// IOSTOUCH_GYRO_MAX_DT (a stall) is skipped, and so is what the phone did
// between two frames more than IOSTOUCH_GYRO_MAX_FRAME apart (the game was
// stopped: it would come all at once), or in the IOSTOUCH_GYRO_TURN_HOLD
// after the screen turned round to the other landscape side (the phone is
// still on its way round). The sensitivity is one of _afGyroSens: at 1.0x
// the view turns as far as the phone does.
#define IOSTOUCH_GYRO_HZ 100.0
#define IOSTOUCH_GYRO_YAW_RELAX 1.41
#define IOSTOUCH_GYRO_SMOOTH 4.0
#define IOSTOUCH_GYRO_SMOOTH_N 12 // about 0.125 s
#define IOSTOUCH_GYRO_SOFT 1.5
#define IOSTOUCH_GYRO_MAX_DT 0.05
#define IOSTOUCH_GYRO_MAX_FRAME 0.5
#define IOSTOUCH_GYRO_TURN_HOLD 0.35
#define IOSTOUCH_GYRO_DEFAULT_SENS 1 // 1.5x

#define IOSTOUCH_MAX_TOUCHES 10

// ---------------------------------------------------------------- buttons

enum {
  KIND_HOLD = 0, // holds its game button while touched
  KIND_PRESS,    // presses its game button once when the touch lifts on it (BOMB: a look swipe can't waste one)
  KIND_MENU,     // asks for the menu when the touch lifts on it; held IOSTOUCH_MENU_HOLD, opens its tray
  KIND_TAP,      // asks for its request when the touch lifts on it
  KIND_HOLDSAVE, // asks for a quick save once held IOSTOUCH_QUICKSAVE_HOLD seconds without leaving it
  KIND_HOLDLOAD, // asks for a quick load once held IOSTOUCH_QUICKLOAD_HOLD seconds without leaving it
  KIND_KEYBOARD, // (MENU's tray) opens or closes the console, when the touch lifts on it
  KIND_FPS,      // (MENU's tray) shows or hides the FPS readout, when the touch lifts on it
  KIND_GYRO,     // (MENU's tray) the next tilt aiming mode, when the touch lifts on it
  KIND_GYROSENS, // (MENU's tray) the next tilt aiming sensitivity, when the touch lifts on it
  KIND_WHEEL,    // NEXT WPN, PREV WPN: a tap presses its game button once as it lifts; a slide or a hold opens the weapon wheel
};

// which modes a button shows in
#define SHOW_PLAY  (1 << IOSTOUCH_GAMEPLAY)
#define SHOW_CONS  (1 << IOSTOUCH_CONSOLE)
#define SHOW_PAUSE (1 << IOSTOUCH_PAUSED)
#define SHOW_ALL   (SHOW_PLAY | SHOW_CONS | SHOW_PAUSE)

typedef struct {
  const char *label;
  int kind;
  unsigned int ulAction; // KIND_HOLD, KIND_PRESS: IOSTOUCH_FIRE...; otherwise IOSTOUCH_REQ_* (0: none)
  double radius;         // points
  int bLookWhileHeld;    // dragging on this button also turns the view
  int iShowIn;           // SHOW_*
  double x, y;           // centre, set in layout
} IOSTouchButton;

// Layout (see IOSTouch_LayoutButtons). Bottom right, under the right thumb:
// FIRE, an arc of CROUCH / USE / JUMP around it, ZOOM right of FIRE and
// BOMB right of JUMP -- all IOSTOUCH_CLUSTER_GAP apart; ZOOM and BOMB only
// show while they can be used. These pass drags through to looking, so a
// thumb that lands on one while aiming keeps aiming -- except BOMB, which
// goes off as the finger lifts on it (bombs are few: a look swipe that
// starts on it mustn't use one up). Top left, below the
// score: next and previous weapon (a tap; slid or held, the weapon wheel). Top right: quick save and quick load
// (each a short hold) and the menu. Holding MENU opens a tray just
// under it: tilt aiming's sensitivity and mode (SENS, GYRO), FPS, which
// shows or hides a frame rate readout by QUICK SAVE, and the keyboard, for
// the console (cheats). RESUME, in the middle, only while the game is paused.
enum {
  BTN_FIRE, BTN_ZOOM, BTN_CROUCH, BTN_USE, BTN_JUMP, BTN_BOMB,
  BTN_NEXTWPN, BTN_PREVWPN,
  BTN_QUICKSAVE, BTN_QUICKLOAD, BTN_MENU,
  BTN_RESUME,
  BTN_TRAYSENS, BTN_TRAYGYRO, BTN_TRAYFPS, BTN_TRAYKEYS, // MENU's tray (left to right), hidden unless it is open
  BTN_COUNT
};
static IOSTouchButton _aButtons[] = {
  [BTN_FIRE]      = { "FIRE",        KIND_HOLD,     IOSTOUCH_FIRE,          42.0, 1, SHOW_PLAY },
  [BTN_ZOOM]      = { "ZOOM",        KIND_HOLD,     IOSTOUCH_ZOOM,          28.0, 1, SHOW_PLAY },
  [BTN_CROUCH]    = { "CROUCH",      KIND_HOLD,     IOSTOUCH_CROUCH,        29.0, 1, SHOW_PLAY },
  [BTN_USE]       = { "USE",         KIND_HOLD,     IOSTOUCH_USE,           29.0, 1, SHOW_PLAY },
  [BTN_JUMP]      = { "JUMP",        KIND_HOLD,     IOSTOUCH_JUMP,          31.0, 1, SHOW_PLAY },
  [BTN_BOMB]      = { "BOMB",        KIND_PRESS,    IOSTOUCH_BOMB,          30.0, 0, SHOW_PLAY },
  [BTN_NEXTWPN]   = { "NEXT\nWPN",   KIND_WHEEL,    IOSTOUCH_NEXTWEAPON,    22.0, 0, SHOW_PLAY },
  [BTN_PREVWPN]   = { "PREV\nWPN",   KIND_WHEEL,    IOSTOUCH_PREVWEAPON,    22.0, 0, SHOW_PLAY },
  [BTN_QUICKSAVE] = { "QUICK\nSAVE", KIND_HOLDSAVE, IOSTOUCH_REQ_QUICKSAVE, 22.0, 0, SHOW_PLAY },
  [BTN_QUICKLOAD] = { "QUICK\nLOAD", KIND_HOLDLOAD, IOSTOUCH_REQ_QUICKLOAD, 22.0, 0, SHOW_PLAY },
  [BTN_MENU]      = { "MENU",        KIND_MENU,     IOSTOUCH_REQ_MENU,      22.0, 0, SHOW_ALL },
  [BTN_RESUME]    = { "RESUME",      KIND_TAP,      IOSTOUCH_REQ_RESUME,    44.0, 0, SHOW_PAUSE },
  [BTN_TRAYSENS]  = { "SENS",        KIND_GYROSENS, 0,                      20.0, 0, SHOW_ALL },
  [BTN_TRAYGYRO]  = { "GYRO",        KIND_GYRO,     0,                      20.0, 0, SHOW_ALL },
  [BTN_TRAYFPS]   = { "FPS",         KIND_FPS,      0,                      20.0, 0, SHOW_ALL },
  [BTN_TRAYKEYS]  = { "",            KIND_KEYBOARD, IOSTOUCH_REQ_CONSOLE,   20.0, 0, SHOW_ALL },
};
#define IOSTOUCH_NUM_BUTTONS ((int)(sizeof(_aButtons) / sizeof(_aButtons[0])))
typedef char IOSTouch_assertButtonCount[(IOSTOUCH_NUM_BUTTONS == BTN_COUNT) ? 1 : -1];

// ------------------------------------------------------- shared with the game
// The game reads these on its own thread (IOSTouch_ReadInput, 20 times a
// second; IOSTouch_TakeLook and IOSTouch_TakeGyro, also every frame): only
// touch them under _lock.

static os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
static int _bReading = 0;         // gameplay controls are showing; otherwise the game gets nothing
static unsigned int _ulHeld = 0;  // game buttons held down by touches
static unsigned int _ulSeen = 0;  // ...that a game tick has seen held since they were pressed
// One-off presses waiting to be read, and the one being read right now
static unsigned char _aPulseQueue[IOSTOUCH_NUMBUTTONS];
static unsigned char _aPulseReads[IOSTOUCH_NUMBUTTONS];
static unsigned char _aPulseGap[IOSTOUCH_NUMBUTTONS];
static float _fMoveX = 0.0f, _fMoveY = 0.0f;
static float _fLookX = 0.0f, _fLookY = 0.0f;
static float _fGyroYaw = 0.0f, _fGyroPitch = 0.0f; // tilt aiming: degrees for the view to turn (+ left) and tilt (+ up)
// The weapon wheel's pick (a weapon number) waiting to be read, and the one
// being read now: reads left, its value, and the read after it with none
static int _iPickPending = 0, _iPickReads = 0, _iPickNow = 0, _bPickGap = 0;

// Sets the game buttons held by touches. ulLifted: buttons whose touch just
// lifted (not cancelled) -- if no tick saw them held, it was a tap quicker
// than a tick (or a KIND_PRESS button, never held), and they are reported as
// one press.
static void IOSTouch_SetHeld(unsigned int ulHeld, unsigned int ulLifted)
{
  os_unfair_lock_lock(&_lock);
  for (int i = 0; i < IOSTOUCH_NUMBUTTONS; i++) {
    const unsigned int ul = 1u << i;
    if ((ulLifted & ul) && !(_ulSeen & ul) && _aPulseQueue[i] < 255) _aPulseQueue[i]++;
  }
  _ulSeen &= ~(ulHeld & ~_ulHeld); // newly pressed: not seen yet
  _ulHeld = ulHeld;
  os_unfair_lock_unlock(&_lock);
}

// Drops everything held and queued; bReading: whether the game gets input now
static void IOSTouch_ResetShared(int bReading)
{
  os_unfair_lock_lock(&_lock);
  _bReading = bReading;
  _ulHeld = _ulSeen = 0;
  memset(_aPulseQueue, 0, sizeof(_aPulseQueue));
  memset(_aPulseReads, 0, sizeof(_aPulseReads));
  memset(_aPulseGap, 0, sizeof(_aPulseGap));
  _fMoveX = _fMoveY = 0.0f;
  _fLookX = _fLookY = 0.0f;
  _fGyroYaw = _fGyroPitch = 0.0f;
  _iPickPending = _iPickReads = _iPickNow = _bPickGap = 0;
  os_unfair_lock_unlock(&_lock);
}

// The weapon wheel picked a weapon: the game gets it in the select field of
// its next free read (IOSTouch_ReadInput); a later pick replaces one still
// waiting
static void IOSTouch_QueuePick(int iWeapon)
{
  os_unfair_lock_lock(&_lock);
  _iPickPending = iWeapon;
  os_unfair_lock_unlock(&_lock);
}

// The weapon wheel opened: a NEXT/PREV tap the game hasn't started reading
// (a slow frame) would go off after the wheel closes and undo its pick, so it
// is dropped (one already being read finishes); look and tilt aiming taken
// before the opening are dropped too, so nothing jumps once the game goes on
static void IOSTouch_SharedWheelOpened(void)
{
  os_unfair_lock_lock(&_lock);
  for (int i = 0; i < IOSTOUCH_NUMBUTTONS; i++) {
    if ((1u << i) & (IOSTOUCH_NEXTWEAPON | IOSTOUCH_PREVWEAPON)) _aPulseQueue[i] = 0;
  }
  _fLookX = _fLookY = 0.0f;
  _fGyroYaw = _fGyroPitch = 0.0f;
  os_unfair_lock_unlock(&_lock);
}

// ---------------------------------------------------------------- layout

// The HUD, and the game's messages, clock and stats, lay themselves out inside
// a frame: the screen less its rounded corners and the home indicator
// (IOSTouch_GetHudFrame). UIKit doesn't give the corners' radius, but a phone's
// side insets in landscape (notch or Dynamic Island) come to about it or a
// little more -- 62 pt on the 18 Pro Max for about 62, 59 for 55 on the 14 Pro,
// 47 for 47.3 on the 12, 44 for 39 on the X -- and so does an iPad's bottom
// inset (20 for 18). The frame's corners go on the screen corners' arcs at 45
// degrees, IOSTOUCH_HUD_CORNER_GAP inside (19.6 pt in on the 18 Pro Max), so
// nothing drawn inside the frame is cut off; its bottom also stays above the
// home indicator (21 pt). Screens without insets have square corners: the
// frame is the whole screen. The camera cutout sits at mid-height by a side:
// the Dynamic Island (side insets 59 pt and up, 126 pt long) is well clear of
// the HUD, but a notch (side insets 44-50 pt, up to about 210 pt long and 33
// pt deep) reaches down to the armour box at the bottom left, so there the
// frame's sides keep 22 pt less than the inset in (the inset is the same on
// both sides).
static void IOSTouch_HudFrameInsets(double inLeft, double inTop, double inRight, double inBottom,
                                    double *pfLeft, double *pfTop, double *pfRight, double *pfBottom)
{
  const double R = fmax(fmax(inLeft, inRight), fmax(inTop, inBottom));
  const double c = (R > IOSTOUCH_HUD_CORNER_GAP) ? R - (R - IOSTOUCH_HUD_CORNER_GAP) / M_SQRT2 : 0.0;
  const double side = fmax(inLeft, inRight);
  *pfLeft = *pfRight = (side >= 40.0 && side < 55.0) ? fmax(c, side - 22.0) : c;
  *pfTop = fmax(inTop, c);
  *pfBottom = fmax(inBottom, c);
}

typedef struct {
  int bValid;
  double x0, y0, x1, y1;
} IOSTouchRect;

// What the layout puts besides the buttons (points): the backing behind
// MENU's tray, the part of it behind its right two buttons (FPS and the
// keyboard: where the FPS readout keeps clear of), and the FPS readout's
// centre
static IOSTouchRect _rTrayBack, _rTrayKeysBack;
static double _fFpsX = 0.0, _fFpsY = 0.0;

static double IOSTouch_DistToRect(double px, double py, const IOSTouchRect *r)
{
  const double cx = fmin(fmax(px, r->x0), r->x1), cy = fmin(fmax(py, r->y0), r->y1);
  return hypot(px - cx, py - cy);
}

// Distance from (px,py) to the segment (ax,ay)-(bx,by)
static double IOSTouch_DistToSegment(double px, double py, double ax, double ay, double bx, double by)
{
  const double vx = bx - ax, vy = by - ay;
  const double len2 = vx * vx + vy * vy;
  double t = len2 > 0 ? ((px - ax) * vx + (py - ay) * vy) / len2 : 0;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  return hypot(px - (ax + t * vx), py - (ay + t * vy));
}

// Whether the box hw x hh either side of (cx,cy) keeps 4pt clear of these
// HUD boxes and 6pt clear of these buttons
static int IOSTouch_BoxIsClear(double cx, double cy, double hw, double hh, const IOSTouchRect *const *apr, int ctRects,
                               const int *aiButtons, int ctButtons)
{
  const IOSTouchRect box = { 1, cx - hw, cy - hh, cx + hw, cy + hh };
  for (int i = 0; i < ctRects; i++) {
    const IOSTouchRect *r = apr[i];
    if (!r->bValid) continue;
    const double dx = fmax(fmax(r->x0 - box.x1, box.x0 - r->x1), 0.0);
    const double dy = fmax(fmax(r->y0 - box.y1, box.y0 - r->y1), 0.0);
    if (hypot(dx, dy) < 4.0) return 0;
  }
  for (int i = 0; i < ctButtons; i++) {
    const IOSTouchButton *b = &_aButtons[aiButtons[i]];
    if (IOSTouch_DistToRect(b->x, b->y, &box) < b->radius + 6.0) return 0;
  }
  return 1;
}

// The HUD's unread messages box as the layout was given it (points): while
// it shows, a touch on it is its own (IOSTouch_IsOnMessages). As a new
// message comes in the HUD drops it down a little for a while: where it was
// drawn last (points, set every frame by IOSTouch_UpdateOverlay) is the
// box's too.
static IOSTouchRect _rMessages;
static IOSTouchRect _rMessagesNow;

// The weapon wheel (points): round the middle of the safe area, 4 pt down,
// as big as fits with room for a slice to pop out (as Jedi Knight's)
static double _fWheelCX = 0.0, _fWheelCY = 0.0, _fWheelR0 = 0.0, _fWheelR1 = 0.0;
static void IOSTouch_WheelGeometry(double W, double H, double inLeft, double inTop, double inRight, double inBottom,
                                   double *pfCX, double *pfCY, double *pfR0, double *pfR1)
{
  const double left = fmax(inLeft, 8.0), right = W - fmax(inRight, 8.0);
  const double top = fmax(inTop, 8.0), bottom = H - fmax(inBottom, 8.0);
  *pfCX = (left + right) * 0.5;
  *pfCY = (top + bottom) * 0.5 + 4.0;
  *pfR1 = fmin(IOSTOUCH_WHEEL_R1_MAX, (bottom - top) * 0.5 - IOSTOUCH_WHEEL_POP - 6.0);
  *pfR0 = round(*pfR1 * IOSTOUCH_WHEEL_R0_FRAC);
}

// Places every button on a W x H point screen with these safe-area insets,
// keeping clear of the HUD's score and high score boxes and unread messages
// box (in points) and of the camera cutout when it may be on the right. (The
// messages box is in the HUD's top row, which only the FPS readout comes
// near. Nothing of the HUD is at the bottom right: the ammo row isn't drawn.)
static void IOSTouch_LayoutButtons(double W, double H, double inLeft, double inTop, double inRight, double inBottom,
                                   int bCutoutMayBeRight, const IOSTouchRect *prScore, const IOSTouchRect *prHiScore,
                                   const IOSTouchRect *prMessages)
{
  _rMessages = *prMessages;

  const double left = fmax(inLeft, 8.0);
  const double right = W - fmax(inRight, 8.0);
  const double top = fmax(inTop, 8.0);
  const double bottom = H - fmax(inBottom, 8.0);

  // FIRE in the corner, above the home indicator. Without side insets there
  // is no spare edge for ZOOM to sit in beside FIRE, so FIRE sits further in.
  const double FR = _aButtons[BTN_FIRE].radius;
  const double fireX = right - (inRight < 20.0 ? 100 : 76), fireY = bottom - 58;
  _aButtons[BTN_FIRE].x = fireX;
  _aButtons[BTN_FIRE].y = fireY;

  // CROUCH, USE and JUMP on an arc around FIRE (angles counter-clockwise from
  // pointing right, so 90 is straight up), 45 degrees apart -- which at this
  // radius leaves about IOSTOUCH_CLUSTER_GAP between them
  const double arc = 115.0;
  const int aArcBtn[3] = { BTN_CROUCH, BTN_USE, BTN_JUMP };
  const double aArcDeg[3] = { 180.0, 135.0, 90.0 };
  for (int i = 0; i < 3; i++) {
    const double rad = aArcDeg[i] * M_PI / 180.0;
    _aButtons[aArcBtn[i]].x = fireX + arc * cos(rad);
    _aButtons[aArcBtn[i]].y = fireY - arc * sin(rad);
  }

  // The camera cutout, when it is on the right, as a capsule along the right
  // edge: the Dynamic Island (side inset ~59-62pt) is ~126x37pt, 11pt in
  // from the edge; a notch (side inset ~44-50pt) is up to ~210x33pt at the
  // edge. The landscape side insets are the same both ways round, so which
  // side it is on comes from the screen's orientation.
  const int bCutout = inRight >= 40.0 && bCutoutMayBeRight;
  const double cutX = (inRight >= 55.0) ? W - 29.5 : W - 16.5;
  const double cutR = (inRight >= 55.0) ? 18.5 : 16.5;
  const double cutHalf = ((inRight >= 55.0) ? 63.0 : 105.0) - cutR;

  // ZOOM: up and to the right of FIRE, IOSTOUCH_CLUSTER_GAP from it, as low as
  // it can sit while staying on screen, clear of JUMP and clear of the
  // cutout. Where the cutout takes that side (on a short screen), level with
  // FIRE or a little below it.
  {
    IOSTouchButton *a = &_aButtons[BTN_ZOOM];
    const IOSTouchButton *j = &_aButtons[BTN_JUMP];
    const double AR = a->radius;
    const double D = FR + AR + IOSTOUCH_CLUSTER_GAP;
    // If nothing at that distance fits, step outwards; failing that, allow
    // ZOOM closer to JUMP.
    double bx = fireX + D * cos(M_PI * 35.0 / 180.0), by = fireY - D * sin(M_PI * 35.0 / 180.0);
    int bFound = 0;
    for (int pass = 0; pass < 2 && !bFound; pass++) {
      const double jumpGap = pass ? 2.0 : 8.0;
      for (int extra = 0; extra <= 80 && !bFound; extra += 2) {
        for (int i = 0; i <= 105; i++) {
          const int deg = (i <= 75) ? 10 + i : 85 - i; // 10 up to 85 degrees, then 9 down to -20
          const double rad = deg * M_PI / 180.0;
          const double px = fireX + (D + extra) * cos(rad), py = fireY - (D + extra) * sin(rad);
          if (px + AR > W - 4 || py - AR < top + 60 || py + AR > bottom) continue;     // on screen, below the top row
          if (hypot(px - j->x, py - j->y) < AR + j->radius + jumpGap) continue;          // clear of JUMP
          if (bCutout && IOSTouch_DistToSegment(px, py, cutX, H * 0.5 - cutHalf, cutX, H * 0.5 + cutHalf) < AR + cutR + 2)
            continue;                                                                     // clear of the cutout
          bx = px;
          by = py;
          bFound = 1;
          break;
        }
      }
    }
    a->x = bx;
    a->y = by;
  }

  // BOMB: right of JUMP and above ZOOM, out of the way of aiming -- on the
  // circle IOSTOUCH_CLUSTER_GAP out from JUMP, as far round towards pointing
  // right as it fits on screen, below the top row and clear of ZOOM, USE,
  // FIRE and the cutout. Where the cutout (or, on smaller
  // screens, ZOOM) takes that spot it goes higher, over JUMP; failing that,
  // the gaps shrink.
  {
    IOSTouchButton *f = &_aButtons[BTN_BOMB];
    const IOSTouchButton *j = &_aButtons[BTN_JUMP];
    const IOSTouchButton *a = &_aButtons[BTN_ZOOM];
    const IOSTouchButton *c = &_aButtons[BTN_USE];
    const IOSTouchButton *d = &_aButtons[BTN_CROUCH];
    const double R = f->radius;
    const double aGap[3] = { IOSTOUCH_CLUSTER_GAP, 20.0, 12.0 };
    // If nothing fits (a very short screen, e.g. with Display Zoom): just
    // outside the arc, IOSTOUCH_CLUSTER_GAP from both CROUCH and USE
    const double dist = d->radius + R + IOSTOUCH_CLUSTER_GAP; // CROUCH and USE are the same size
    const double mx = (d->x + c->x) * 0.5, my = (d->y + c->y) * 0.5;
    const double vx = c->x - d->x, vy = c->y - d->y;
    const double L = sqrt(vx * vx + vy * vy);
    const double h = (dist > L * 0.5) ? sqrt(dist * dist - L * L * 0.25) : 0;
    double nx = vy / L, ny = -vx / L; // the perpendicular pointing away from FIRE
    if ((mx - fireX) * nx + (my - fireY) * ny < 0) { nx = -nx; ny = -ny; }
    double bx = mx + nx * h, by = my + ny * h;
    int bFound = 0;
    for (int pass = 0; pass < 3 && !bFound; pass++) {
      const double gap = aGap[pass];
      const double D = j->radius + R + gap;
      for (int deg = 0; deg <= 135; deg++) {
        const double rad = deg * M_PI / 180.0;
        const double px = j->x + D * cos(rad), py = j->y - D * sin(rad);
        if (px + R > W - 4 || py - R < top + 60) continue;                    // on screen, below the top row
        if (hypot(px - a->x, py - a->y) < R + a->radius + gap) continue;     // clear of ZOOM
        if (hypot(px - c->x, py - c->y) < R + c->radius + gap) continue;     // USE
        if (hypot(px - fireX, py - fireY) < R + FR + gap) continue;          // FIRE
        if (bCutout && IOSTouch_DistToSegment(px, py, cutX, H * 0.5 - cutHalf, cutX, H * 0.5 + cutHalf) < R + cutR + 2)
          continue;                                                          // the cutout
        bx = px;
        by = py;
        bFound = 1;
        break;
      }
    }
    f->x = bx;
    f->y = by;
  }

  // Top left: NEXT WPN | PREV WPN, below the score box
  double topLeftY = top + 26;
  if (prScore->bValid) topLeftY = fmax(topLeftY, prScore->y1 + 4 + _aButtons[BTN_NEXTWPN].radius);
  _aButtons[BTN_NEXTWPN].x = left + 24;
  _aButtons[BTN_PREVWPN].x = left + 84;
  _aButtons[BTN_NEXTWPN].y = _aButtons[BTN_PREVWPN].y = topLeftY;
  // Top right: QUICK SAVE, QUICK LOAD, MENU in the corner -- spaced well
  // apart, so a press meant for one of the two quick holds can't land on the
  // other
  _aButtons[BTN_QUICKSAVE].x = right - 156;
  _aButtons[BTN_QUICKLOAD].x = right - 90;
  _aButtons[BTN_MENU].x = right - 24;
  _aButtons[BTN_QUICKSAVE].y = _aButtons[BTN_QUICKLOAD].y = _aButtons[BTN_MENU].y = top + 26;

  // MENU's tray: a row just under the corner, the keyboard right below MENU
  // (a held thumb slides straight down onto it), then FPS, GYRO and SENS
  // to the left, IOSTOUCH_TRAY_STEP apart. Where BOMB, ZOOM or JUMP sits high
  // in that corner (a smaller screen) the row moves left until it is clear of
  // them -- or, if that never happens, to wherever it is furthest from them.
  // (While open, the tray is on top and takes its own touches, but a touch
  // meant for it mustn't land nearer one of those.)
  {
    const IOSTouchButton *m = &_aButtons[BTN_MENU];
    const int aAvoid[3] = { BTN_BOMB, BTN_ZOOM, BTN_JUMP };
    const double ty = m->y + 52;
    const double row = (BTN_TRAYKEYS - BTN_TRAYSENS) * IOSTOUCH_TRAY_STEP; // SENS to the keyboard
    double kx = m->x, bestGap = -1e9;
    for (double x = m->x; x >= m->x - 240; x -= 4) {
      double gap = 1e9;
      for (int i = 0; i < 3; i++) {
        const IOSTouchButton *f = &_aButtons[aAvoid[i]];
        gap = fmin(gap, IOSTouch_DistToSegment(f->x, f->y, x - row, ty, x, ty) - 26 - f->radius);
      }
      if (gap > bestGap) {
        bestGap = gap;
        kx = x;
      }
      if (gap >= 8) break;
    }
    for (int i = BTN_TRAYSENS; i <= BTN_TRAYKEYS; i++) {
      _aButtons[i].x = kx - (BTN_TRAYKEYS - i) * IOSTOUCH_TRAY_STEP;
      _aButtons[i].y = ty;
    }
    _rTrayBack.bValid = 1;
    _rTrayBack.x0 = kx - row - 26;
    _rTrayBack.y0 = ty - 26;
    _rTrayBack.x1 = kx + 26;
    _rTrayBack.y1 = ty + 26;
    _rTrayKeysBack = _rTrayBack;
    _rTrayKeysBack.x0 = kx - IOSTOUCH_TRAY_STEP - 26;
  }

  // The FPS readout where the keyboard button used to be, left of QUICK SAVE:
  // the game prints its messages at the top left, and its high score box is
  // in the middle. Where that spot is on the high score box or the unread
  // messages box right of it (a narrower screen, a larger HUD), it moves right
  // towards QUICK SAVE; if it never fits there, it goes below QUICK SAVE (and
  // on to the left), clear of BOMB, ZOOM and MENU's tray's FPS and keyboard
  // as well. (Where the rest of the open tray lies over it, it hides while
  // the tray is open: IOSTouch_FpsUnderTray.)
  {
    const IOSTouchButton *q = &_aButtons[BTN_QUICKSAVE];
    const IOSTouchRect *const apr[4] = { prScore, prHiScore, prMessages, &_rTrayKeysBack };
    const int aAvoid[2] = { BTN_BOMB, BTN_ZOOM };
    const double hw = IOSTOUCH_FPS_W * 0.5, hh = IOSTOUCH_FPS_H * 0.5;
    const double y2 = q->y + q->radius + 8 + hh;
    int bFound = 0;
    _fFpsX = right - 216;
    _fFpsY = top + 26;
    for (double x = right - 216; x <= q->x - q->radius - 6 - hw && !bFound; x += 2) {
      if (IOSTouch_BoxIsClear(x, top + 26, hw, hh, apr, 3, NULL, 0)) {
        _fFpsX = x;
        bFound = 1;
      }
    }
    for (double x = q->x; x >= left + hw && !bFound; x -= 4) {
      if (IOSTouch_BoxIsClear(x, y2, hw, hh, apr, 4, aAvoid, 2)) {
        _fFpsX = x;
        _fFpsY = y2;
        bFound = 1;
      }
    }
  }

  // RESUME in the middle of the screen, below the game's "Paused" (centred
  // at 0.4 of the height of the HUD's frame)
  {
    double fl, ft, fr, fb;
    IOSTouch_HudFrameInsets(inLeft, inTop, inRight, inBottom, &fl, &ft, &fr, &fb);
    _aButtons[BTN_RESUME].x = (left + right) * 0.5;
    _aButtons[BTN_RESUME].y = fmax((top + bottom) * 0.5, ft + (H - ft - fb) * 0.4 + 60.0);
  }

  // The weapon wheel, over the middle of the screen
  IOSTouch_WheelGeometry(W, H, inLeft, inTop, inRight, inBottom, &_fWheelCX, &_fWheelCY, &_fWheelR0, &_fWheelR1);
}

// A HUD box (fractions of the screen) in points
static IOSTouchRect IOSTouch_RectInPoints(const IOSTouchRect *prFrac, double W, double H)
{
  IOSTouchRect r = { 0, 0, 0, 0, 0 };
  if (prFrac->bValid) {
    r.bValid = 1;
    r.x0 = prFrac->x0 * W;
    r.y0 = prFrac->y0 * H;
    r.x1 = prFrac->x1 * W;
    r.y1 = prFrac->y1 * H;
  }
  return r;
}

static int IOSTouch_SameRect(const IOSTouchRect *a, const IOSTouchRect *b)
{
  if (a->bValid != b->bValid) return 0;
  if (!a->bValid) return 1;
  return fabs(a->x0 - b->x0) < 0.5 && fabs(a->y0 - b->y0) < 0.5 && fabs(a->x1 - b->x1) < 0.5 && fabs(a->y1 - b->y1) < 0.5;
}

// Keeps a box the HUD drew (it reports none for parts it didn't draw)
static void IOSTouch_KeepRect(IOSTouchRect *prFrac, const float af[4])
{
  if (af[2] > af[0] && af[3] > af[1]) {
    prFrac->bValid = 1;
    prFrac->x0 = af[0];
    prFrac->y0 = af[1];
    prFrac->x1 = af[2];
    prFrac->y1 = af[3];
  }
}

// The HUD's frame (fractions of the screen), from the game view's size and
// safe-area insets once a frame (IOSTouch_UpdateOverlay)
static float _afHudFrame[4] = { 0.0f, 0.0f, 1.0f, 1.0f };

static void IOSTouch_SetHudFrame(double W, double H, double inLeft, double inTop, double inRight, double inBottom)
{
  if (W <= 0.0 || H <= 0.0) return;
  double fl, ft, fr, fb;
  IOSTouch_HudFrameInsets(inLeft, inTop, inRight, inBottom, &fl, &ft, &fr, &fb);
  _afHudFrame[0] = (float)(fl / W);
  _afHudFrame[1] = (float)(ft / H);
  _afHudFrame[2] = (float)(1.0 - fr / W);
  _afHudFrame[3] = (float)(1.0 - fb / H);
}

void IOSTouch_GetHudFrame(float afFrame[4])
{
  memcpy(afFrame, _afHudFrame, sizeof(_afHudFrame));
}

// ---------------------------------------------------------------- touches
// Main thread. The overlay view hands each touch to IOSTouch_TouchBegan /
// Passed / Moved / Ended (points, seconds) and calls IOSTouch_TickHolds once
// a frame; it shows what the state below says.

typedef enum {
  ROLE_NONE = 0,
  ROLE_STICK,
  ROLE_LOOK,
  ROLE_BUTTON,
  ROLE_IGNORED,  // not on a button while only buttons are live, or only closed MENU's tray; ignored until it lifts
  ROLE_MESSAGES, // on the HUD's messages box (a tap: all read; held: NETRICSA)
  ROLE_WHEEL,    // on the open weapon wheel (or the NEXT/PREV touch that opened it)
} IOSTouchRole;

typedef struct {
  const void *touch;    // the UITouch: only compared, never used after it ends (NULL: a free slot)
  IOSTouchRole role;
  int button;
  double x, y;          // where it is now
  double tDown;         // when it began
  int bFired;           // QUICK SAVE, QUICK LOAD: the hold is over (a save or load was asked for, by this finger or
                        // another one on either button, or it slid off). MENU: the hold is over (tray opened, or
                        // slid off). The unread messages box: the touch does nothing more (NETRICSA was asked for,
                        // by this finger or another one on the box, or it slid off, or the box went away)
  int trayButton;       // MENU, after its tray opened: the tray button under the finger, or -1
  // The messages box: where the finger landed, the box as it was laid out then and where the HUD drew it then
  // (IOSTouch_StillOnMessages)
  // (also NEXT WPN, PREV WPN: where it went down, a slide's distance and aim being measured from there)
  double xDown, yDown;
  IOSTouchRect rLaidDown, rNowDown;
  // NEXT WPN, PREV WPN: when it went down by the touch's own clock (UITouch.timestamp: a tap is told from a
  // hold by it, so a slow frame between the two doesn't make a tap long). bFired: no tap any more (it slid or
  // held while the wheel couldn't open). On the wheel: the slice picked (an index into the wheel's map,
  // IOSTOUCH_WHEEL_CANCEL, or -1); whether it is the touch that opened it, and opened it by holding still (it
  // is open to tap until this slides IOSTOUCH_WHEEL_DEAD), whether it has slid out of the dead zone, where
  // its slide is measured from and which way it points (degrees, counter-clockwise from pointing right)
  double tDownTouch;
  int wheelSlot;
  int bWheelOpener, bWheelHeld, bArmed;
  double wheelOriginX, wheelOriginY;
  double wheelAim;
  unsigned int uSeq;    // the order the touches went down in (IOSTouch_WheelPointed: the newest finger)
} IOSTouchSlot;

static IOSTouchSlot _aSlots[IOSTOUCH_MAX_TOUCHES];
static unsigned int _uTouchSeq = 0;
static int _aButtonHeld[IOSTOUCH_NUM_BUTTONS]; // touches on each button
static int _bStickActive = 0;
static double _fStickOriginX = 0.0, _fStickOriginY = 0.0; // where the stick's thumb came down
static float _fStickX = 0.0f, _fStickY = 0.0f;           // -1..1 of the radius, screen axes
static int _iMode = IOSTOUCH_HIDDEN;
static int _iRequests = 0;                 // IOSTOUCH_REQ_* not handed out yet
static IOSTouchHud _hud;                   // the latest HUD state
static int _bTrayOpen = 0;                 // MENU's tray
static int _bShowFps = 0;                  // the FPS readout (the view keeps it in the app's settings)
// how far QUICK SAVE's, QUICK LOAD's and MENU's hold rings, and the unread
// messages box's, have filled
static float _fSaveRing = 0.0f, _fLoadRing = 0.0f, _fMenuRing = 0.0f, _fMessagesRing = 0.0f;
static double _tLastTick = 0.0;            // when IOSTouch_TickHolds last ran (0: not since the last reset)
// The FPS readout: frames counted since _ulFpsFrames at _tFpsBase, and the
// number it shows (-1: none measured yet)
static int _bFpsBase = 0;
static unsigned int _ulFpsFrames = 0;
static double _tFpsBase = 0.0;
static int _iFpsShown = -1;
// Tilt aiming: its mode and sensitivity (an index into _afGyroSens; the view
// keeps both in the app's settings), whether the device has device motion
// (the view sets it) and whether iOS refused it; whether the motion updates
// are running, whether the last frame could have aimed (and when it was);
// the landscape side the screen was last turned and when it turned round to
// it. Under _gyroLock, as the samples come in on the motion queue: which way
// round the screen is (+1 landscape left, -1 landscape right, 0 neither, so
// no aiming), how far the view is to turn (degrees, + left) and tilt (+ up)
// for the samples since the last frame, what the samples keep (the last
// one's time, the smoothing's), and whether one came back refused.
enum { IOSTOUCH_GYRO_OFF = 0, IOSTOUCH_GYRO_TOUCH, IOSTOUCH_GYRO_ALWAYS, IOSTOUCH_GYRO_NUM_MODES };
static const float _afGyroSens[] = { 1.0f, 1.5f, 2.0f, 3.0f };
#define IOSTOUCH_GYRO_NUM_SENS ((int)(sizeof(_afGyroSens) / sizeof(_afGyroSens[0])))
static int _iGyroMode = IOSTOUCH_GYRO_OFF; // until it is switched on in MENU's tray
static int _iGyroSens = IOSTOUCH_GYRO_DEFAULT_SENS;
static int _bGyroAvailable = 0;
static int _bGyroRefused = 0;
static int _bGyroRunning = 0;
static int _bGyroWasOk = 0;
static double _tGyroLastFrame = 0.0;
static int _iGyroLastSide = 0;
static double _tGyroTurnedRound = -1.0e9;
static os_unfair_lock _gyroLock = OS_UNFAIR_LOCK_INIT;
static int _iGyroSide = 0;
static double _fGyroQueueYaw = 0.0, _fGyroQueuePitch = 0.0;
static double _tGyroLastSample = 0.0;
static double _afGyroSmooth[IOSTOUCH_GYRO_SMOOTH_N][2];
static int _iGyroSmoothNext = 0;
static int _bGyroRefusedOnQueue = 0;

// Whether this device has what tilt aiming needs (not the Simulator), and
// iOS hasn't refused it
static int IOSTouch_GyroAvailable(void)
{
  return _bGyroAvailable && !_bGyroRefused;
}

// The next mode or sensitivity (MENU's tray's GYRO and SENS)
static void IOSTouch_GyroNextMode(void)
{
  _iGyroMode = (_iGyroMode + 1) % IOSTOUCH_GYRO_NUM_MODES;
}
static void IOSTouch_GyroNextSens(void)
{
  _iGyroSens = (_iGyroSens + 1) % IOSTOUCH_GYRO_NUM_SENS;
}

// Whether a button shows now
static int IOSTouch_IsShown(int button)
{
  if (!(_aButtons[button].iShowIn & (1 << _iMode))) return 0;
  if (button == BTN_ZOOM) return _hud.bValid && _hud.bSniper;
  if (button == BTN_BOMB) return _hud.bValid && _hud.ctBombs > 0;
  if (button >= BTN_TRAYSENS && button <= BTN_TRAYKEYS) return _bTrayOpen;
  return 1;
}

// What BOMB says: how many serious bombs there are, as the HUD's bomb box at
// the bottom right did on PC (it isn't drawn on iOS). BOMB only shows with
// one or more.
static void IOSTouch_BombLabel(int ctBombs, char *str, size_t size)
{
  if (ctBombs > 0) snprintf(str, size, "BOMB\n%d", ctBombs);
  else snprintf(str, size, "BOMB");
}

// Closest showing button the touch is on (with a little forgiveness), so a
// touch in the gap between two buttons picks the nearer one rather than the
// first listed. The open MENU tray is drawn on top of the rest, so its
// buttons come first: anywhere on its backing (which reaches as far round
// each as that forgiveness does) is on the nearest one, the corners between
// two of them too.
static int IOSTouch_ButtonAt(double x, double y)
{
  int best = -1;
  double bestDist = 0;
  const IOSTouchButton *l = &_aButtons[BTN_TRAYSENS], *r = &_aButtons[BTN_TRAYKEYS];
  if (_bTrayOpen && IOSTouch_DistToSegment(x, y, l->x, l->y, r->x, r->y) <= 26.0) {
    for (int i = BTN_TRAYSENS; i <= BTN_TRAYKEYS; i++) {
      const double d = fabs(x - _aButtons[i].x);
      if (best < 0 || d < bestDist) {
        best = i;
        bestDist = d;
      }
    }
    return best;
  }
  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    const IOSTouchButton *b = &_aButtons[i];
    if (!IOSTouch_IsShown(i)) continue;
    const double d = hypot(x - b->x, y - b->y);
    if (d <= b->radius + 6.0 && (best < 0 || d - b->radius < bestDist)) {
      best = i;
      bestDist = d - b->radius;
    }
  }
  return best;
}

static int IOSTouch_IsOnButton(double x, double y, int button)
{
  const IOSTouchButton *b = &_aButtons[button];
  return hypot(x - b->x, y - b->y) <= b->radius + 6.0;
}

static int IOSTouch_IsTrayButton(int button);

// Whether a finger lifting at (x,y) lifts on the button it came down on: on
// it -- or, for one of the open tray's, anywhere on the backing nearer it
// than the others (as IOSTouch_ButtonAt has it)
static int IOSTouch_LiftsOnButton(double x, double y, int button)
{
  return IOSTouch_IsOnButton(x, y, button) || (IOSTouch_IsTrayButton(button) && IOSTouch_ButtonAt(x, y) == button);
}

// Whether the HUD's messages box shows now: in a game being played, while the
// HUD draws it (blinking with unread messages, dim without; not at all with
// the HUD's messages turned off)
static int IOSTouch_MessagesShown(void)
{
  return _iMode == IOSTOUCH_GAMEPLAY && _hud.bValid && _hud.bMessages && _rMessages.bValid;
}

// Whether (x,y) is on the unread messages box, while it shows: where it sits
// or where it was drawn last (with a little forgiveness, but never on the
// FPS readout, which isn't part of it). A button within reach takes the
// touch first (IOSTouch_TouchBegan).
static int IOSTouch_IsOnMessages(double x, double y)
{
  if (!IOSTouch_MessagesShown()) return 0;
  if (IOSTouch_DistToRect(x, y, &_rMessages) > IOSTOUCH_MESSAGES_REACH
      && !(_rMessagesNow.bValid && IOSTouch_DistToRect(x, y, &_rMessagesNow) <= IOSTOUCH_MESSAGES_REACH)) return 0;
  return !(_bShowFps && fabs(x - _fFpsX) <= IOSTOUCH_FPS_W * 0.5 && fabs(y - _fFpsY) <= IOSTOUCH_FPS_H * 0.5);
}

// Whether a touch that came down on the messages box (s) is still on it at
// (x,y): while the box shows, laid out as it was then, the finger on it --
// or still where it landed, once the HUD has drawn the box somewhere else
// since (a new message drops it down a little and back up again, under a
// finger kept still: that finger mustn't count as having slid off)
static int IOSTouch_StillOnMessages(const IOSTouchSlot *s, double x, double y)
{
  if (!IOSTouch_MessagesShown() || !IOSTouch_SameRect(&s->rLaidDown, &_rMessages)) return 0;
  if (IOSTouch_IsOnMessages(x, y)) return 1;
  return !IOSTouch_SameRect(&s->rNowDown, &_rMessagesNow)
         && hypot(x - s->xDown, y - s->yDown) <= IOSTOUCH_MESSAGES_REACH;
}

static int IOSTouch_IsTrayButton(int button)
{
  return button >= BTN_TRAYSENS && button <= BTN_TRAYKEYS;
}

// QUICK SAVE and QUICK LOAD: the holds that end for good when the finger leaves the button
static int IOSTouch_IsQuickHold(int button)
{
  return button == BTN_QUICKSAVE || button == BTN_QUICKLOAD;
}

static IOSTouchSlot *IOSTouch_FindSlot(const void *touch)
{
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    if (_aSlots[i].touch == touch) return &_aSlots[i];
  }
  return NULL;
}

// The stick as movement: nothing inside the dead zone, full speed from
// IOSTOUCH_STICK_FULL of the radius out, in the direction it is pushed
static void IOSTouch_SetMoveFromStick(void)
{
  float fX = 0.0f, fY = 0.0f;
  const float fLen = sqrtf(_fStickX * _fStickX + _fStickY * _fStickY);
  if (_bStickActive && fLen > IOSTOUCH_STICK_DEADZONE) {
    float fSpeed = (fLen - IOSTOUCH_STICK_DEADZONE) / (IOSTOUCH_STICK_FULL - IOSTOUCH_STICK_DEADZONE);
    if (fSpeed > 1.0f) fSpeed = 1.0f;
    fX = _fStickX / fLen * fSpeed;
    fY = -_fStickY / fLen * fSpeed; // up the screen is forward
  }
  os_unfair_lock_lock(&_lock);
  _fMoveX = fX;
  _fMoveY = fY;
  os_unfair_lock_unlock(&_lock);
}

// The game buttons the touches on KIND_HOLD buttons hold down
static unsigned int IOSTouch_HeldButtons(void)
{
  unsigned int ul = 0;
  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    if (_aButtonHeld[i] && _aButtons[i].kind == KIND_HOLD) ul |= _aButtons[i].ulAction;
  }
  return ul;
}

// Opens or closes MENU's tray. Closing it lets go of any touch on its buttons.
static void IOSTouch_SetTrayOpen(int bOpen)
{
  bOpen = bOpen != 0;
  if (_bTrayOpen == bOpen) return;
  _bTrayOpen = bOpen;
  if (!bOpen) {
    for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
      IOSTouchSlot *s = &_aSlots[i];
      if (!s->touch || s->role != ROLE_BUTTON) continue;
      if (IOSTouch_IsTrayButton(s->button)) {
        if (_aButtonHeld[s->button] > 0) _aButtonHeld[s->button]--;
        s->role = ROLE_IGNORED;
      }
      s->trayButton = -1;
    }
  }
}

// Shows or hides the FPS readout; it starts counting afresh
static void IOSTouch_SetShowFps(int bShow)
{
  _bShowFps = bShow != 0;
  _bFpsBase = 0;
  _iFpsShown = -1;
}

// A tray button picked: it does its thing, and the tray closes -- except
// after GYRO and SENS, which stay for another tap to go on to the next (with
// no gyro, they do nothing)
static void IOSTouch_UseTrayButton(int button)
{
  const int kind = _aButtons[button].kind;
  if (kind == KIND_KEYBOARD) {
    _iRequests |= _aButtons[button].ulAction; // the console, with the iOS keyboard
  }
  else if (kind == KIND_FPS) {
    IOSTouch_SetShowFps(!_bShowFps);
  }
  else if ((kind == KIND_GYRO || kind == KIND_GYROSENS) && IOSTouch_GyroAvailable()) {
    if (kind == KIND_GYRO) IOSTouch_GyroNextMode();
    else IOSTouch_GyroNextSens();
  }
  if (kind != KIND_GYRO && kind != KIND_GYROSENS) IOSTouch_SetTrayOpen(0);
}

// ---------------------------------------------------------------- weapon wheel
// One slice per weapon of the game, in the order NEXT WPN goes through them
// (Second Encounter: PlayerWeapons.es's aiWeaponsRemap; First Encounter: its
// weapons' own order), clockwise from the bottom left, the gap at the bottom
// to cancel. The weapon numbers are the game's (WeaponType, the HUD's
// _awiWeapons index). Each slice is tinted by the HUD's ammo type of its
// weapon: the two shotguns share one, as do the tommygun and the minigun (they
// share their ammo, and show the same count). The name shows in the middle,
// on two lines where it doesn't fit one: at its middle space, or after the
// hyphen given here.
enum { WCOL_NONE = 0, WCOL_SHELLS, WCOL_BULLETS, WCOL_ROCKETS, WCOL_GRENADES, WCOL_NAPALM, WCOL_SNIPER,
       WCOL_ELECTRICITY, WCOL_CANNONBALLS, WCOL_COUNT };
static const unsigned char _aubWheelColours[WCOL_COUNT][3] = {
  { 255, 214, 120 }, { 255, 160, 80 }, { 120, 200, 255 }, { 255, 105, 90 }, { 110, 220, 170 },
  { 255, 190, 60 }, { 190, 150, 255 }, { 90, 230, 230 }, { 200, 200, 215 },
};
typedef struct {
  int iWeapon;
  int iColour;
  const char *strName;
  const char *strName2; // on two lines ("\n"), when it has no space to break at
} IOSTouchWheelSlot;
typedef struct {
  const IOSTouchWheelSlot *aSlots;
  int ctSlots;
  double fSliceDeg; // each slice's width; the gap at the bottom is what is left
} IOSTouchWheelMap;
#define IOSTOUCH_WHEEL_MAX 14
static const IOSTouchWheelSlot _aWheelTSE[] = {
  {  1, WCOL_NONE,        "KNIFE",            NULL }, { 10, WCOL_NONE,        "CHAINSAW",         NULL },
  {  2, WCOL_NONE,        "COLT",             NULL }, {  3, WCOL_NONE,        "TWO COLTS",        NULL },
  {  4, WCOL_SHELLS,      "SHOTGUN",          NULL }, {  5, WCOL_SHELLS,      "DOUBLE SHOTGUN",   NULL },
  {  6, WCOL_BULLETS,     "TOMMYGUN",         NULL }, {  7, WCOL_BULLETS,     "MINIGUN",          NULL },
  {  8, WCOL_ROCKETS,     "ROCKET LAUNCHER",  NULL }, {  9, WCOL_GRENADES,    "GRENADE LAUNCHER", NULL },
  { 11, WCOL_NAPALM,      "FLAMETHROWER",     "FLAME-\nTHROWER" }, { 13, WCOL_SNIPER, "SNIPER RIFLE", NULL },
  { 12, WCOL_ELECTRICITY, "LASERGUN",         "LASER-\nGUN" },     { 14, WCOL_CANNONBALLS, "CANNON", NULL },
};
static const IOSTouchWheelSlot _aWheelTFE[] = {
  {  1, WCOL_NONE,        "KNIFE",            NULL }, {  2, WCOL_NONE,        "COLT",             NULL },
  {  3, WCOL_NONE,        "TWO COLTS",        NULL }, {  4, WCOL_SHELLS,      "SHOTGUN",          NULL },
  {  5, WCOL_SHELLS,      "DOUBLE SHOTGUN",   NULL }, {  6, WCOL_BULLETS,     "TOMMYGUN",         NULL },
  {  7, WCOL_BULLETS,     "MINIGUN",          NULL }, {  8, WCOL_ROCKETS,     "ROCKET LAUNCHER",  NULL },
  {  9, WCOL_GRENADES,    "GRENADE LAUNCHER", NULL }, { 14, WCOL_ELECTRICITY, "LASERGUN",         "LASER-\nGUN" },
  { 16, WCOL_CANNONBALLS, "CANNON",           NULL },
};
static const IOSTouchWheelMap _aWheelMaps[2] = {
  [IOSTOUCH_WHEEL_TSE] = { _aWheelTSE, (int)(sizeof(_aWheelTSE) / sizeof(_aWheelTSE[0])), 23.0 },
  [IOSTOUCH_WHEEL_TFE] = { _aWheelTFE, (int)(sizeof(_aWheelTFE) / sizeof(_aWheelTFE[0])), 29.0 },
};
typedef char IOSTouch_assertWheelSize[(sizeof(_aWheelTSE) / sizeof(_aWheelTSE[0]) <= IOSTOUCH_WHEEL_MAX
                                       && sizeof(_aWheelTFE) / sizeof(_aWheelTFE[0]) <= IOSTOUCH_WHEEL_MAX) ? 1 : -1];

// A slice's state, from what the game says (never the weapons mask's bits
// alone: the First Encounter's cheat sets bits of weapons that don't exist)
enum { WSTATE_READY = 0, WSTATE_NOAMMO, WSTATE_NOTFOUND };

// What the game said last (IOSTouch_SetWeapons); the wheel: open or not
// (and whether open to tap a slice), the button that opened it and the map
// it shows; the NEXT/PREV hold rings; what was pointed at last and the haptic
// ticks the view still has to give (one each time the thumb moves onto
// another slice or the gap)
static IOSTouchWeapons _wpn;
static int _bWheelOpen = 0, _bWheelTapMode = 0, _iWheelButton = BTN_NEXTWPN, _iWheelMap = IOSTOUCH_WHEEL_TSE;
static float _afWheelRing[2] = { 0.0f, 0.0f }; // NEXT WPN's, PREV WPN's
static int _iWheelHot = -1;
static int _ctWheelTicks = 0;

static int IOSTouch_WheelIsOpen(void)
{
  return _bWheelOpen;
}

int IOSTouch_HoldsGame(void)
{
  return _bWheelOpen && _iMode == IOSTOUCH_GAMEPLAY;
}

// Whether the game would take a pick now: the player there, alive, no
// cutscene camera, not walked by the game
static int IOSTouch_WheelCanOpen(void)
{
  return _wpn.bValid && _wpn.bCanSelect;
}

static const IOSTouchWheelMap *IOSTouch_WheelMapOf(int iMap)
{
  return &_aWheelMaps[(iMap == IOSTOUCH_WHEEL_TFE) ? IOSTOUCH_WHEEL_TFE : IOSTOUCH_WHEEL_TSE];
}

// A slice's middle (degrees, counter-clockwise from pointing right): the
// first one's edge at the gap's left edge, then clockwise
static double IOSTouch_WheelSlotDeg(const IOSTouchWheelMap *m, int i)
{
  const double gap = 360.0 - m->ctSlots * m->fSliceDeg;
  return 270.0 - gap * 0.5 - m->fSliceDeg * 0.5 - i * m->fSliceDeg;
}

static int IOSTouch_WheelSlotStateIn(const IOSTouchWeapons *pw, int iWeapon)
{
  if (!(pw->ulOwned & (1u << iWeapon))) return WSTATE_NOTFOUND;
  if (!(pw->ulReady & (1u << iWeapon))) return WSTATE_NOAMMO;
  return WSTATE_READY;
}

static int IOSTouch_WheelSlotState(int i)
{
  return IOSTouch_WheelSlotStateIn(&_wpn, IOSTouch_WheelMapOf(_iWheelMap)->aSlots[i].iWeapon);
}

// The ammo count a slice shows (the HUD's, at most 999), or -1 for none: the
// knife, chainsaw and colts have none, infinite ammo shows none, nor does a
// weapon not found yet
static int IOSTouch_WheelSlotCount(int i)
{
  const int w = IOSTouch_WheelMapOf(_iWheelMap)->aSlots[i].iWeapon;
  if (_wpn.bInfiniteAmmo || IOSTouch_WheelSlotStateIn(&_wpn, w) == WSTATE_NOTFOUND || _wpn.aiAmmo[w] < 0) return -1;
  return _wpn.aiAmmo[w] > 999 ? 999 : _wpn.aiAmmo[w];
}

// Whether a slice is picked when lifted on: a weapon the game would switch to
// -- not the one in hand (picking that again would only change the knife's
// stance)
static int IOSTouch_WheelCanPick(int i)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  if (i < 0 || i >= m->ctSlots) return 0;
  return IOSTouch_WheelSlotState(i) == WSTATE_READY && m->aSlots[i].iWeapon != _wpn.iWanted;
}

static double IOSTouch_AngleDiff(double a, double b)
{
  double d = fmod(a - b, 360.0);
  if (d > 180.0) d -= 360.0;
  if (d < -180.0) d += 360.0;
  return d;
}

// The slice a direction (degrees) points into, or IOSTOUCH_WHEEL_CANCEL in
// the gap at the bottom. The slice already picked (cur) holds on
// IOSTOUCH_WHEEL_HYST past its edges.
static int IOSTouch_WheelSliceForAngle(double deg, int cur)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  const double half = m->fSliceDeg * 0.5;
  if (cur >= 0 && cur < m->ctSlots && fabs(IOSTouch_AngleDiff(deg, IOSTouch_WheelSlotDeg(m, cur))) <= half + IOSTOUCH_WHEEL_HYST)
    return cur;
  int best = IOSTOUCH_WHEEL_CANCEL;
  double bestDiff = 0.0;
  for (int i = 0; i < m->ctSlots; i++) {
    const double d = fabs(IOSTouch_AngleDiff(deg, IOSTouch_WheelSlotDeg(m, i)));
    if (d <= half && (best < 0 || d < bestDiff)) {
      best = i;
      bestDiff = d;
    }
  }
  return best;
}

// The slice under (x,y) (cur as above): anywhere on it by its angle, from a
// little inside the hole's edge out to past a popped-out slice's;
// IOSTOUCH_WHEEL_CANCEL in the gap at the bottom; -1 off the ring (the middle,
// or well outside it)
static int IOSTouch_WheelSliceAt(double x, double y, int cur)
{
  const double dx = x - _fWheelCX, dy = _fWheelCY - y;
  const double r = sqrt(dx * dx + dy * dy);
  if (r < _fWheelR0 - 4.0 || r > _fWheelR1 + IOSTOUCH_WHEEL_POP + 14.0) return -1;
  return IOSTouch_WheelSliceForAngle(atan2(dy, dx) * 180.0 / M_PI, cur);
}

// The opener's slide: the direction from where it went down picks the slice.
// Inside the dead zone nothing is picked (once it has been out, lifting there
// cancels); the point it is measured from trails behind the thumb. Dragged
// onto the wheel itself, the slice under the thumb is picked instead (none
// in the middle, the gap cancels). Back where it went down, nothing is
// picked, however far it went. (Jedi Knight's aimWheel.)
static void IOSTouch_WheelAim(IOSTouchSlot *s, double x, double y)
{
  double dx = x - s->wheelOriginX, dy = y - s->wheelOriginY;
  double r = sqrt(dx * dx + dy * dy);
  if (r > IOSTOUCH_WHEEL_LEASH) {
    const double k = (r - IOSTOUCH_WHEEL_LEASH) / r;
    s->wheelOriginX += dx * k;
    s->wheelOriginY += dy * k;
    dx = x - s->wheelOriginX;
    dy = y - s->wheelOriginY;
    r = IOSTOUCH_WHEEL_LEASH;
  }
  const double cx = x - _fWheelCX, cy = _fWheelCY - y;
  if (sqrt(cx * cx + cy * cy) <= _fWheelR1 + IOSTOUCH_WHEEL_POP + 14.0) {
    s->bArmed = 1;
    s->wheelAim = atan2(cy, cx) * 180.0 / M_PI;
    s->wheelSlot = IOSTouch_WheelSliceAt(x, y, s->wheelSlot);
    return;
  }
  if (s->bArmed && hypot(x - s->xDown, y - s->yDown) < IOSTOUCH_WHEEL_DEAD) {
    s->wheelOriginX = s->xDown;
    s->wheelOriginY = s->yDown;
    s->wheelSlot = -1;
    return;
  }
  if (r < IOSTOUCH_WHEEL_DEAD) {
    s->wheelSlot = -1;
    return;
  }
  s->bArmed = 1;
  s->wheelAim = atan2(-dy, dx) * 180.0 / M_PI;
  s->wheelSlot = IOSTouch_WheelSliceForAngle(s->wheelAim, s->wheelSlot);
}

// What is pointed at on the open wheel: by the opener once it has slid, else
// by the newest other finger on it (an opener that opened it by holding still
// points at nothing until it slides). A slice, IOSTOUCH_WHEEL_CANCEL (the
// gap), or -1; *pbCancel: lifting would cancel (the gap, back in the dead
// zone, or a finger off the ring); *ppSlide: the sliding opener, if it points.
static int IOSTouch_WheelPointed(int *pbCancel, const IOSTouchSlot **ppSlide)
{
  const IOSTouchSlot *pSlide = NULL, *pFinger = NULL;
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    const IOSTouchSlot *s = &_aSlots[i];
    if (!s->touch || s->role != ROLE_WHEEL) continue;
    if (s->bWheelOpener && s->bWheelHeld) continue;
    if (s->bWheelOpener && !_bWheelTapMode) pSlide = s;
    else if (!pFinger || s->uSeq > pFinger->uSeq) pFinger = s;
  }
  int hot = -1, bCancel = 0;
  if (pSlide && pSlide->bArmed) {
    hot = pSlide->wheelSlot;
    bCancel = hot < 0;
  }
  else if (pFinger) {
    hot = pFinger->wheelSlot;
    bCancel = hot < 0;
    pSlide = NULL;
  }
  else {
    pSlide = NULL;
  }
  if (pbCancel) *pbCancel = _bWheelOpen && bCancel;
  if (ppSlide) *ppSlide = _bWheelOpen ? pSlide : NULL;
  return _bWheelOpen ? hot : -1;
}

static int IOSTouch_WheelHot(void)
{
  return IOSTouch_WheelPointed(NULL, NULL);
}

// After every touch on the open wheel: a haptic tick each time the thumb
// moves onto another slice or the gap (not when it leaves them)
static void IOSTouch_WheelUpdateHot(void)
{
  const int hot = IOSTouch_WheelHot();
  if (hot != _iWheelHot) {
    if (hot != -1) _ctWheelTicks++;
    _iWheelHot = hot;
  }
}

// Opens the wheel from a press on NEXT WPN or PREV WPN (s): slid (to slide to
// a slice, measured from where it went down) or held still (bHeld: to tap
// one). Every other touch lets go of what it held and is ignored until it
// lifts (a press waiting on the other button too); MENU's tray closes; the
// stick stops. The game holds still until it closes (IOSTouch_HoldsGame).
static void IOSTouch_WheelOpen(IOSTouchSlot *s, int bHeld)
{
  IOSTouch_SetTrayOpen(0);
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    IOSTouchSlot *o = &_aSlots[i];
    if (!o->touch) continue;
    if (o->role == ROLE_BUTTON && _aButtonHeld[o->button] > 0) _aButtonHeld[o->button]--;
    if (o->role == ROLE_STICK) {
      _bStickActive = 0;
      _fStickX = _fStickY = 0.0f;
    }
    if (o != s) o->role = ROLE_IGNORED;
  }
  _fSaveRing = _fLoadRing = _fMenuRing = _fMessagesRing = 0.0f;
  _afWheelRing[0] = _afWheelRing[1] = 0.0f;
  IOSTouch_SetMoveFromStick();
  IOSTouch_SharedWheelOpened();
  _bWheelOpen = 1;
  _bWheelTapMode = bHeld != 0;
  _iWheelButton = s->button;
  _iWheelMap = (_wpn.iMap == IOSTOUCH_WHEEL_TFE) ? IOSTOUCH_WHEEL_TFE : IOSTOUCH_WHEEL_TSE;
  s->role = ROLE_WHEEL;
  s->bWheelOpener = 1;
  s->bWheelHeld = bHeld != 0;
  s->bArmed = 0;
  s->wheelSlot = -1;
  s->wheelOriginX = s->xDown;
  s->wheelOriginY = s->yDown;
  _iWheelHot = -1;
  IOSTouch_WheelUpdateHot();
  IOSTouch_SetHeld(IOSTouch_HeldButtons(), 0);
}

// Closes the wheel, picking what is in slice i if it can be picked (the game
// gets it as soon as it goes on: IOSTouch_ReadInput). Fingers still on it are
// ignored until they lift.
static void IOSTouch_WheelClose(int i)
{
  if (_bWheelOpen && IOSTouch_WheelCanPick(i)) IOSTouch_QueuePick(IOSTouch_WheelMapOf(_iWheelMap)->aSlots[i].iWeapon);
  for (int t = 0; t < IOSTOUCH_MAX_TOUCHES; t++) {
    if (_aSlots[t].touch && _aSlots[t].role == ROLE_WHEEL) _aSlots[t].role = ROLE_IGNORED;
  }
  _bWheelOpen = 0;
  _bWheelTapMode = 0;
  _iWheelHot = -1;
}

// A press on NEXT WPN or PREV WPN still waiting to see which gesture it is
static int IOSTouch_IsWheelPress(const IOSTouchSlot *s)
{
  return s->touch && s->role == ROLE_BUTTON && _aButtons[s->button].kind == KIND_WHEEL;
}

// A wheel press slid IOSTOUCH_WHEEL_OPEN_SLIDE from where it went down: the
// wheel opens, to slide -- or, if it can't now, the press is no tap any more
// either. Returns whether it opened.
static int IOSTouch_WheelPressSlid(IOSTouchSlot *s, double x, double y)
{
  if (!IOSTouch_IsWheelPress(s) || s->bFired || hypot(x - s->xDown, y - s->yDown) < IOSTOUCH_WHEEL_OPEN_SLIDE) return 0;
  if (!IOSTouch_WheelCanOpen()) {
    s->bFired = 1;
    _afWheelRing[s->button == BTN_PREVWPN] = 0.0f;
    return 0;
  }
  IOSTouch_WheelOpen(s, 0);
  return 1;
}

// What the game says, every frame before IOSTouch_Update. The wheel closes,
// picking nothing, once the game couldn't take a pick (the player died, a
// cutscene's camera, a level change).
void IOSTouch_SetWeapons(const IOSTouchWeapons *pw)
{
  _wpn = *pw;
  if (_bWheelOpen && !IOSTouch_WheelCanOpen()) IOSTouch_WheelClose(-1);
}

// ------------------------------------------------- the wheel's icons
// The HUD's own weapon icons, which the game hands over from its data
// (IOS_GetWeaponIcon, asked for by the main loop between frames:
// IOSTouch_WantedIcons): kept for the process, each as it is and tinted for
// the states that grey it (IOSTouch_TintIcon). The two colts show the colt's.
#define IOSTOUCH_ICON_MAX 64
enum { WICON_READY = 0, WICON_NOAMMO, WICON_NOTFOUND, WICON_NUM };
typedef struct {
  int bHave, bGaveUp, bAsked;
  double tAsked;
  int w, h;
  unsigned char aub[WICON_NUM][IOSTOUCH_ICON_MAX * IOSTOUCH_ICON_MAX * 4];
} IOSTouchIcon;
static IOSTouchIcon _aIcons[IOSTOUCH_WPN_MAX];
static unsigned int _ulIconsNew = 0; // icons the view hasn't made images of yet

// The icon a weapon shows: the two colts the colt's
static int IOSTouch_WheelIconOf(int iWeapon)
{
  return iWeapon == 3 ? 2 : iWeapon;
}

// A state's tint of an icon (RGBA, not premultiplied): grey (luma x k), alpha
// x a -- no ammo 0.80 / 0.70, not found yet 0.40 / 0.45, so the two read
// apart and a weapon not found yet is a faint silhouette
static void IOSTouch_TintIcon(const unsigned char *pubSrc, int ctTexels, int iState, unsigned char *pubDst)
{
  if (iState == WICON_READY) {
    memcpy(pubDst, pubSrc, (size_t)ctTexels * 4);
    return;
  }
  const float k = (iState == WICON_NOAMMO) ? 0.80f : 0.40f;
  const float a = (iState == WICON_NOAMMO) ? 0.70f : 0.45f;
  for (int i = 0; i < ctTexels; i++) {
    const unsigned char *p = pubSrc + i * 4;
    const float lum = 0.299f * p[0] + 0.587f * p[1] + 0.114f * p[2];
    float v = lum * k + 0.5f, al = p[3] * a + 0.5f;
    if (v > 255.0f) v = 255.0f;
    if (al > 255.0f) al = 255.0f;
    pubDst[i * 4 + 0] = pubDst[i * 4 + 1] = pubDst[i * 4 + 2] = (unsigned char)v;
    pubDst[i * 4 + 3] = (unsigned char)al;
  }
}

unsigned int IOSTouch_WantedIcons(double tNow)
{
  if (_iMode != IOSTOUCH_GAMEPLAY || !_wpn.bValid) return 0;
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_wpn.iMap);
  unsigned int ul = 0;
  for (int i = 0; i < m->ctSlots; i++) {
    const int w = IOSTouch_WheelIconOf(m->aSlots[i].iWeapon);
    IOSTouchIcon *pi = &_aIcons[w];
    if (pi->bHave || pi->bGaveUp || (ul & (1u << w))) continue;
    if (pi->bAsked && tNow - pi->tAsked < 1.0) continue;
    pi->bAsked = 1;
    pi->tAsked = tNow;
    ul |= 1u << w;
  }
  return ul;
}

void IOSTouch_SetWeaponIcon(int iWeapon, const unsigned char *pubRGBA, int iWidth, int iHeight)
{
  if (iWeapon <= 0 || iWeapon >= IOSTOUCH_WPN_MAX) return;
  IOSTouchIcon *pi = &_aIcons[iWeapon];
  if (!pubRGBA || iWidth <= 0 || iHeight <= 0 || iWidth > IOSTOUCH_ICON_MAX || iHeight > IOSTOUCH_ICON_MAX) {
    if (!pi->bHave) pi->bGaveUp = 1; // its name shows instead
    _ulIconsNew |= 1u << iWeapon;
    return;
  }
  pi->w = iWidth;
  pi->h = iHeight;
  for (int st = 0; st < WICON_NUM; st++) IOSTouch_TintIcon(pubRGBA, iWidth * iHeight, st, pi->aub[st]);
  pi->bHave = 1;
  pi->bGaveUp = 0;
  _ulIconsNew |= 1u << iWeapon;
}

// ------------------------------------------------- the wheel's layout
// Each slice shows its icon in a box IOSTOUCH_WHEEL_ICON x k points square,
// and under it, IOSTOUCH_WHEEL_ROW_GAP down, its ammo count in a row as tall
// as the digits (IOSTOUCH_WHEEL_AMMO_INK of the IOSTOUCH_WHEEL_AMMO_FONT x k
// pt font) and as wide as "000". The two are fitted as one block, upright,
// IOSTOUCH_WHEEL_BLOCK_MARGIN inside the slice as drawn (a degree in from
// its edges) and the hole, every slice with the row (so the layout never
// depends on the counts); k is the largest of 1.15, 1.10 ... 0.60 at which
// every slice's block fits, one for the wheel. Each block sits at the middle
// of the stretch of its slice's middle line where it fits; a slice without a
// count centres its icon in the block. A slice that pops out takes its block
// out IOSTOUCH_WHEEL_POP_SHIFT, the icon IOSTOUCH_WHEEL_POP_ICON as big.
#define IOSTOUCH_WHEEL_ICON 32.0
#define IOSTOUCH_WHEEL_ROW_GAP 2.0
#define IOSTOUCH_WHEEL_AMMO_FONT 9.0
#define IOSTOUCH_WHEEL_AMMO_INK 0.705
#define IOSTOUCH_WHEEL_ROW_W (3 * 0.6 * IOSTOUCH_WHEEL_AMMO_FONT) // "000" in the system font's monospaced digits
#define IOSTOUCH_WHEEL_BLOCK_MARGIN 2.0
#define IOSTOUCH_WHEEL_POP_SHIFT 5.0
#define IOSTOUCH_WHEEL_POP_ICON 1.08

typedef struct {
  int iMap;
  double R0, R1;
  double k;                         // the icons' scale (0: nothing fits)
  double afR[IOSTOUCH_WHEEL_MAX];   // each block's middle, from the wheel's centre
} IOSTouchWheelFit;

// The block's size at scale k
static void IOSTouch_WheelBlockSize(double k, double *pfW, double *pfH)
{
  const double B = IOSTOUCH_WHEEL_ICON * k;
  *pfW = fmax(B, IOSTOUCH_WHEEL_ROW_W * k);
  *pfH = B + IOSTOUCH_WHEEL_ROW_GAP + IOSTOUCH_WHEEL_AMMO_FONT * IOSTOUCH_WHEEL_AMMO_INK * k;
}

// Whether a w x h block centred at (cx,cy) (y up, from the wheel's centre)
// is IOSTOUCH_WHEEL_BLOCK_MARGIN inside the slice at th (radians), drawn half
// either side, between the radii R0 and R1
static int IOSTouch_WheelBlockFits(double cx, double cy, double w, double h, double th, double half, double R0, double R1)
{
  const double M = IOSTOUCH_WHEEL_BLOCK_MARGIN;
  const double xs[2] = { cx - w * 0.5, cx + w * 0.5 }, ys[2] = { cy - h * 0.5, cy + h * 0.5 };
  for (int i = 0; i < 2; i++) {
    for (int j = 0; j < 2; j++) {
      if (hypot(xs[i], ys[j]) > R1 - M) return 0;
    }
  }
  const double nx = fmin(fmax(0.0, xs[0]), xs[1]), ny = fmin(fmax(0.0, ys[0]), ys[1]); // nearest the centre
  if (hypot(nx, ny) < R0 + M) return 0;
  // the slice's two edges, lines through the centre, and their inward normals
  const double a1 = th + half, a2 = th - half;
  const double an[2][2] = { { sin(a1), -cos(a1) }, { -sin(a2), cos(a2) } };
  for (int n = 0; n < 2; n++) {
    for (int i = 0; i < 2; i++) {
      for (int j = 0; j < 2; j++) {
        if (xs[i] * an[n][0] + ys[j] * an[n][1] < M) return 0;
      }
    }
  }
  return 1;
}

// The stretch of a slice's middle line where the block fits at scale k: its
// middle (0: nowhere)
static double IOSTouch_WheelBlockPlace(const IOSTouchWheelMap *m, int i, double k, double R0, double R1)
{
  double w, h;
  IOSTouch_WheelBlockSize(k, &w, &h);
  const double th = IOSTouch_WheelSlotDeg(m, i) * M_PI / 180.0;
  const double half = (m->fSliceDeg * 0.5 - 1.0) * M_PI / 180.0;
  double rIn = -1.0, rOut = -1.0;
  const int n = 400;
  for (int j = 0; j <= n; j++) {
    const double r = R0 + (R1 - R0) * j / n;
    if (IOSTouch_WheelBlockFits(r * cos(th), r * sin(th), w, h, th, half, R0, R1)) {
      if (rIn < 0.0) rIn = r;
      rOut = r;
    }
  }
  return rIn < 0.0 ? 0.0 : (rIn + rOut) * 0.5;
}

static void IOSTouch_WheelFitFor(int iMap, double R0, double R1, IOSTouchWheelFit *pf)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(iMap);
  memset(pf, 0, sizeof(*pf));
  pf->iMap = iMap;
  pf->R0 = R0;
  pf->R1 = R1;
  for (int n = 0; n <= 11; n++) {
    const double k = (115 - 5 * n) / 100.0;
    int bAll = 1;
    for (int i = 0; i < m->ctSlots && bAll; i++) {
      pf->afR[i] = IOSTouch_WheelBlockPlace(m, i, k, R0, R1);
      bAll = pf->afR[i] > 0.0;
    }
    if (bAll) {
      pf->k = k;
      return;
    }
  }
  // nothing fits (never on a phone or iPad screen): the smallest, in the middle of the ring
  pf->k = 0.60;
  for (int i = 0; i < m->ctSlots; i++) pf->afR[i] = (R0 + R1) * 0.5;
}

// The open wheel's fit (made again only when the map or the size changes)
static IOSTouchWheelFit _wheelFit;
static const IOSTouchWheelFit *IOSTouch_WheelFit(void)
{
  if (_wheelFit.k <= 0.0 || _wheelFit.iMap != _iWheelMap || _wheelFit.R0 != _fWheelR0 || _wheelFit.R1 != _fWheelR1) {
    IOSTouch_WheelFitFor(_iWheelMap, _fWheelR0, _fWheelR1, &_wheelFit);
  }
  return &_wheelFit;
}

// Where slice i draws its icon box and its count's row (points): popped out
// or not, with a count (the icon at the block's top, the row under it) or
// without (the icon in the block's middle)
static void IOSTouch_WheelSlotRects(int i, int bPopped, int bCount, IOSTouchRect *prIcon, IOSTouchRect *prRow)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  const IOSTouchWheelFit *f = IOSTouch_WheelFit();
  const double th = IOSTouch_WheelSlotDeg(m, i) * M_PI / 180.0;
  const double r = f->afR[i] + (bPopped ? IOSTOUCH_WHEEL_POP_SHIFT : 0.0);
  const double bx = _fWheelCX + r * cos(th), by = _fWheelCY - r * sin(th);
  double w, h;
  IOSTouch_WheelBlockSize(f->k, &w, &h);
  const double B = IOSTOUCH_WHEEL_ICON * f->k, rowH = IOSTOUCH_WHEEL_AMMO_FONT * IOSTOUCH_WHEEL_AMMO_INK * f->k;
  const double iy = bCount ? by - h * 0.5 + B * 0.5 : by; // the icon's middle
  const double s = B * (bPopped ? IOSTOUCH_WHEEL_POP_ICON : 1.0) * 0.5;
  const IOSTouchRect rIcon = { 1, bx - s, iy - s, bx + s, iy + s };
  const double ry = by - h * 0.5 + B + IOSTOUCH_WHEEL_ROW_GAP + rowH * 0.5;
  const IOSTouchRect rRow = { bCount, bx - IOSTOUCH_WHEEL_ROW_W * f->k * 0.5, ry - rowH * 0.5, bx + IOSTOUCH_WHEEL_ROW_W * f->k * 0.5, ry + rowH * 0.5 };
  if (prIcon) *prIcon = rIcon;
  if (prRow) *prRow = rRow;
}

// ------------------------------------------------- the middle
// What the middle says: the name of what is pointed at (or of the weapon in
// hand), its count "37 / 50", and a hint. The view lays it out with
// IOSTouch_WheelMiddleLayout, measuring its own fonts.
enum { WTITLE_SLOT = 0, WTITLE_GREY, WTITLE_WHITE };
typedef struct {
  const char *strTitle;
  const char *strTitle2;  // on two lines, if it has no space to break at (else NULL)
  int iTitleLook;         // WTITLE_*
  int iColour;            // WTITLE_SLOT: the slice's WCOL_*
  char strCount[24];      // "" for none
  const char *strHint;
  int iHot;               // what is pointed at (IOSTouch_WheelPointed)
  int bCancel;
} IOSTouchWheelMiddle;

static void IOSTouch_WheelMiddleState(IOSTouchWheelMiddle *pm)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  memset(pm, 0, sizeof(*pm));
  pm->iHot = IOSTouch_WheelPointed(&pm->bCancel, NULL);
  int i = pm->iHot;
  if (i < 0 && !pm->bCancel) {
    // nothing pointed at: the weapon in hand
    for (int j = 0; j < m->ctSlots; j++) {
      if (m->aSlots[j].iWeapon == _wpn.iWanted) i = j;
    }
    pm->strHint = _bWheelTapMode ? "tap a weapon" : "slide toward a weapon";
    if (i < 0) {
      pm->strTitle = "WEAPONS";
      pm->iTitleLook = WTITLE_WHITE;
      return;
    }
  }
  if (i < 0) {
    pm->strTitle = "CANCEL";
    pm->iTitleLook = WTITLE_WHITE;
    pm->strHint = "lift to cancel";
    return;
  }
  const IOSTouchWheelSlot *sl = &m->aSlots[i];
  const int st = IOSTouch_WheelSlotState(i);
  pm->strTitle = sl->strName;
  pm->strTitle2 = sl->strName2;
  pm->iTitleLook = (st == WSTATE_READY) ? WTITLE_SLOT : WTITLE_GREY;
  pm->iColour = sl->iColour;
  const int ct = IOSTouch_WheelSlotCount(i);
  if (ct >= 0) {
    const int mx = _wpn.aiMaxAmmo[sl->iWeapon];
    snprintf(pm->strCount, sizeof(pm->strCount), "%d / %d", ct, mx < 0 ? 0 : (mx > 999 ? 999 : mx));
  }
  if (pm->iHot >= 0) {
    pm->strHint = (st == WSTATE_READY) ? "lift to select" : ((st == WSTATE_NOAMMO) ? "no ammo" : "not found yet");
  }
}

// The middle's lines, stacked and centred on the wheel's centre: the title
// (WLINE_TITLE: bold 17 pt), the count (semibold 11 pt), the hint (semibold
// 10 pt), 2 pt between the three, each line 1.18 times its size tall. Each
// line keeps within the hole's chord at its height (measured
// IOSTOUCH_WHEEL_NEEDLE_CLEAR in from the hole's edge, at the height of its
// capitals, 0.75 of its size); an item's lines share one size, no smaller
// than its smallest scale (title 0.6, count 0.8, hint 0.7; the title 0.5
// where nothing fits so). The title and the hint may go on two lines; the
// count may be left out (the slice shows it). For each way of stacking them
// the sizes are searched for: the count as large as fits, then the title
// and the hint as large as fits. Of the ways that fit, the one that keeps
// the count, then has the larger of the title's and the hint's smaller
// scale, then the larger sum of the two, then the fewest lines. Returns how
// many lines (0: nothing fits).
enum { WLINE_TITLE = 0, WLINE_COUNT, WLINE_HINT };
typedef double (*IOSTouchTextWidth)(const char *str, int iKind, double fSize, void *pUser);
typedef struct {
  char str[64];
  int iKind;
  double fSize;
  double fDY; // the line's middle, below the wheel's centre
} IOSTouchMiddleLine;
#define IOSTOUCH_MIDDLE_LINES 5

// Text on two lines at its middle space ("a\nb"), or as given; 0 if it can't
static int IOSTouch_SplitLine(const char *str, const char *str2, char *a, char *b, size_t size)
{
  if (str2) {
    const char *nl = strchr(str2, '\n');
    snprintf(a, size, "%.*s", (int)(nl - str2), str2);
    snprintf(b, size, "%s", nl + 1);
    return 1;
  }
  const int n = (int)strlen(str);
  int best = -1;
  for (int i = 0; i < n; i++) {
    if (str[i] == ' ' && (best < 0 || fabs(i - n * 0.5) < fabs(best - n * 0.5))) best = i;
  }
  if (best < 0) return 0;
  snprintf(a, size, "%.*s", best, str);
  snprintf(b, size, "%s", str + best + 1);
  return 1;
}

// One way to stack the middle's lines (a candidate of IOSTouch_WheelMiddleLayout): the lines, how many items
// they are, each line's width at its item's nominal size, and the radius the chords are measured on
typedef struct {
  IOSTouchMiddleLine a[IOSTOUCH_MIDDLE_LINES];
  int n, ctItems;
  double afNomW[IOSTOUCH_MIDDLE_LINES];
  double r;
} IOSTouchMiddleStack;
static const double _afMiddleNom[3] = { 17.0, 11.0, 10.0 };

// Lays the lines out at these sizes (points, per item): each line's middle, and the chord it has
static void IOSTouch_MiddlePlace(IOSTouchMiddleStack *c, const double afSize[3], double afRoom[IOSTOUCH_MIDDLE_LINES])
{
  double h = 2.0 * (c->ctItems - 1);
  for (int j = 0; j < c->n; j++) h += afSize[c->a[j].iKind] * 1.18;
  double y = -h * 0.5;
  for (int j = 0; j < c->n; j++) {
    if (j > 0 && c->a[j].iKind != c->a[j - 1].iKind) y += 2.0;
    const double sz = afSize[c->a[j].iKind], lh = sz * 1.18;
    c->a[j].fSize = sz;
    c->a[j].fDY = y + lh * 0.5;
    y += lh;
    const double yy = fabs(c->a[j].fDY) + sz * 0.75 * 0.5;
    afRoom[j] = 2.0 * sqrt(fmax(0.0, c->r * c->r - yy * yy));
  }
}

// Whether every line keeps within its chord with the items at these scales of their nominal sizes (a line's
// width taken as its nominal width times the scale)
static int IOSTouch_MiddleFitsAt(IOSTouchMiddleStack *c, const double afScale[3])
{
  double afSize[3], afRoom[IOSTOUCH_MIDDLE_LINES];
  for (int k = 0; k < 3; k++) afSize[k] = _afMiddleNom[k] * afScale[k];
  IOSTouch_MiddlePlace(c, afSize, afRoom);
  for (int j = 0; j < c->n; j++) {
    if (c->afNomW[j] * afScale[c->a[j].iKind] > afRoom[j] + 1e-6) return 0;
  }
  return 1;
}

// Item k's scale grown as far as it goes (up to 1), the others as they are; it fits at afScale[k] already.
// A smaller item is narrower and makes the stack shorter, so this halves the step between a scale that fits
// and one that doesn't; whatever it ends on is one that was seen to fit.
#define IOSTOUCH_MIDDLE_STEPS 20
static void IOSTouch_MiddleGrow(IOSTouchMiddleStack *c, double afScale[3], int k)
{
  double ok = afScale[k];
  afScale[k] = 1.0;
  if (IOSTouch_MiddleFitsAt(c, afScale)) return;
  double bad = 1.0;
  for (int i = 0; i < IOSTOUCH_MIDDLE_STEPS; i++) {
    afScale[k] = 0.5 * (ok + bad);
    if (IOSTouch_MiddleFitsAt(c, afScale)) ok = afScale[k];
    else bad = afScale[k];
  }
  afScale[k] = ok;
}

static int IOSTouch_WheelMiddleLayout(double R0, const IOSTouchWheelMiddle *pm, IOSTouchTextWidth pfnWidth, void *pUser,
                                      IOSTouchMiddleLine aOut[IOSTOUCH_MIDDLE_LINES])
{
  const double *afNom = _afMiddleNom;
  const int bCount = pm->strCount[0] != 0;
  char aT[2][64], aH[2][64];
  const int bCanSplitT = IOSTouch_SplitLine(pm->strTitle, pm->strTitle2, aT[0], aT[1], sizeof(aT[0]));
  const int bCanSplitH = IOSTouch_SplitLine(pm->strHint, NULL, aH[0], aH[1], sizeof(aH[0]));
  int ctBest = 0;
  double afKey[3] = { -1.0, -1.0, -1.0 };
  int bBestCount = -1;
  // (should nothing fit, the title may go to half its size; no name, hint and count needs it on any screen)
  for (int pass = 0; pass < 2 && ctBest == 0; pass++) {
  const double afMin[3] = { pass ? 0.5 : 0.6, 0.8, 0.7 };
  for (int cand = 0; cand < 8; cand++) {
    const int bWrapT = (cand >> 2) & 1, bWrapH = (cand >> 1) & 1, bWith2 = !(cand & 1);
    if ((bWrapT && !bCanSplitT) || (bWrapH && !bCanSplitH)) continue;
    IOSTouchMiddleStack st;
    IOSTouchMiddleLine *a = st.a;
    int n = 0;
    if (bWrapT) {
      for (int j = 0; j < 2; j++) { snprintf(a[n].str, sizeof(a[n].str), "%s", aT[j]); a[n++].iKind = WLINE_TITLE; }
    }
    else {
      snprintf(a[n].str, sizeof(a[n].str), "%s", pm->strTitle);
      a[n++].iKind = WLINE_TITLE;
    }
    if (bWith2 && bCount) {
      snprintf(a[n].str, sizeof(a[n].str), "%s", pm->strCount);
      a[n++].iKind = WLINE_COUNT;
    }
    if (bWrapH) {
      for (int j = 0; j < 2; j++) { snprintf(a[n].str, sizeof(a[n].str), "%s", aH[j]); a[n++].iKind = WLINE_HINT; }
    }
    else {
      snprintf(a[n].str, sizeof(a[n].str), "%s", pm->strHint);
      a[n++].iKind = WLINE_HINT;
    }
    st.n = n;
    st.ctItems = (bWith2 && bCount) ? 3 : 2;
    st.r = R0 - IOSTOUCH_WHEEL_NEEDLE_CLEAR;
    for (int j = 0; j < n; j++) st.afNomW[j] = pfnWidth(a[j].str, a[j].iKind, afNom[a[j].iKind], pUser);
    // The sizes are searched for, not only shrunk from the nominal ones (a title shrunk to fit a tall stack
    // can grow again once the stack is shorter): first the count, as large as fits with the title and hint
    // at their smallest; then the title and the hint together, at the largest scale they can share (each
    // no smaller than its own smallest); then whichever of the two grows the further on its own
    double afScale[3] = { afMin[0], afMin[1], afMin[2] };
    if (!IOSTouch_MiddleFitsAt(&st, afScale)) continue;
    IOSTouch_MiddleGrow(&st, afScale, WLINE_COUNT);
    {
      const double lo = fmin(afMin[0], afMin[2]);
      double ok = lo, bad = 1.0, s = 1.0;
      afScale[0] = afScale[2] = 1.0;
      if (!IOSTouch_MiddleFitsAt(&st, afScale)) {
        for (int i = 0; i < IOSTOUCH_MIDDLE_STEPS; i++) {
          s = 0.5 * (ok + bad);
          afScale[0] = fmax(s, afMin[0]);
          afScale[2] = fmax(s, afMin[2]);
          if (IOSTouch_MiddleFitsAt(&st, afScale)) ok = s;
          else bad = s;
        }
        s = ok;
      }
      afScale[0] = fmax(s, afMin[0]);
      afScale[2] = fmax(s, afMin[2]);
    }
    double afT[3] = { afScale[0], afScale[1], afScale[2] }, afH[3] = { afScale[0], afScale[1], afScale[2] };
    IOSTouch_MiddleGrow(&st, afT, WLINE_TITLE);
    IOSTouch_MiddleGrow(&st, afH, WLINE_HINT);
    const double *afPick = (afT[0] + afT[2] >= afH[0] + afH[2]) ? afT : afH;
    double afSize[3], afRoom[IOSTOUCH_MIDDLE_LINES];
    for (int k = 0; k < 3; k++) afSize[k] = afNom[k] * afPick[k];
    // Measured as drawn (the view's fonts needn't scale exactly with size): an item with a line still over
    // its chord shrinks to fit it, until none is (sizes only go down here, so the stack only gets shorter)
    for (int it = 0; it <= 8; it++) {
      IOSTouch_MiddlePlace(&st, afSize, afRoom);
      if (it == 8) break;
      int bShrunk = 0;
      for (int k = 0; k < 3; k++) {
        double f = 1.0;
        for (int j = 0; j < n; j++) {
          if (a[j].iKind != k) continue;
          const double w = pfnWidth(a[j].str, k, afSize[k], pUser);
          if (w > afRoom[j] + 1e-6) f = fmin(f, afRoom[j] / w);
        }
        if (f < 1.0) {
          afSize[k] *= f;
          bShrunk = 1;
        }
      }
      if (!bShrunk) break;
    }
    // The result as laid out: every line within its chord, every item at or above its smallest scale
    int bOk = 1;
    for (int j = 0; j < n; j++) {
      const int k = a[j].iKind;
      if (afSize[k] < afNom[k] * afMin[k] - 1e-9 || pfnWidth(a[j].str, k, afSize[k], pUser) > afRoom[j] + 1e-6) bOk = 0;
    }
    if (!bOk) continue;
    const double ts = afSize[WLINE_TITLE] / afNom[WLINE_TITLE], hs = afSize[WLINE_HINT] / afNom[WLINE_HINT];
    const int bKeeps = bWith2 || !bCount;
    const double k1 = round(fmin(ts, hs) * 1000.0) / 1000.0, k2 = round((ts + hs) * 1000.0) / 1000.0, k3 = -n;
    const int bBetter = ctBest == 0 || bKeeps > bBestCount
                        || (bKeeps == bBestCount && (k1 > afKey[0] || (k1 == afKey[0] && (k2 > afKey[1] || (k2 == afKey[1] && k3 > afKey[2])))));
    if (bBetter) {
      bBestCount = bKeeps;
      afKey[0] = k1;
      afKey[1] = k2;
      afKey[2] = k3;
      ctBest = n;
      memcpy(aOut, a, sizeof(a[0]) * n);
    }
  }
  }
  return ctBest;
}

// ------------------------------------------------- the wheel's looks
// A slice's colour, k of the way to it from the wheel's dark grey (RGB 0..1)
static void IOSTouch_WheelMix(int iColour, double k, float af[4])
{
  for (int c = 0; c < 3; c++) af[c] = (float)((_aubWheelColours[iColour][c] * k + 32.0 * (1.0 - k)) / 255.0);
  af[3] = 1.0f;
}
static void IOSTouch_Grey(double v, double a, float af[4])
{
  af[0] = af[1] = af[2] = (float)v;
  af[3] = (float)a;
}

// Whether dark text (grey 0.08) reads better than white on this colour: the
// higher contrast of the two by WCAG's relative luminance (on the rockets'
// popped red white does, 4.7:1 to dark's 3.9:1; on the others dark does)
static double IOSTouch_Luminance(const float af[4])
{
  double l = 0.0;
  static const double afW[3] = { 0.2126, 0.7152, 0.0722 };
  for (int c = 0; c < 3; c++) {
    const double v = af[c];
    l += afW[c] * (v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4));
  }
  return l;
}
static int IOSTouch_DarkReads(const float afFill[4])
{
  const float afDark[4] = { 0.08f, 0.08f, 0.08f, 1.0f };
  const double lf = IOSTouch_Luminance(afFill), ld = IOSTouch_Luminance(afDark);
  return (lf + 0.05) / (ld + 0.05) >= (1.0 + 0.05) / (lf + 0.05);
}

// How slice i looks now (the view draws it so; the colours RGBA 0..1). A
// weapon it can switch to in its ammo type's colour, the weapon in hand
// edged in white, the one pointed at popped out and brighter; one out of
// ammo in a darker shade, its icon grey; one not found yet dark, its icon a
// faint silhouette, no count.
typedef struct {
  int iState;          // WSTATE_*
  int bHot, bWanted, bPopped;
  float afFill[4], afEdge[4];
  double fLine;        // the edge's width
  int iIcon;           // WICON_*: which tint of its icon
  int iCount;          // the count under the icon, -1: none
  float afText[4];     // the count's colour (and the name's, while it has no icon)
} IOSTouchWheelLook;

static void IOSTouch_WheelSlotLook(int i, int iHot, IOSTouchWheelLook *pl)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  const IOSTouchWheelSlot *sl = &m->aSlots[i];
  memset(pl, 0, sizeof(*pl));
  pl->iState = IOSTouch_WheelSlotState(i);
  pl->bHot = i == iHot;
  pl->bWanted = sl->iWeapon == _wpn.iWanted;
  pl->iCount = IOSTouch_WheelSlotCount(i);
  pl->fLine = 2.0;
  if (pl->iState == WSTATE_READY) {
    pl->bPopped = pl->bHot && !pl->bWanted;
    pl->iIcon = WICON_READY;
    IOSTouch_WheelMix(sl->iColour, pl->bPopped ? 0.70 : 0.42, pl->afFill);
    if (pl->bPopped) IOSTouch_Grey(1.0, 1.0, pl->afEdge);
    else IOSTouch_WheelMix(sl->iColour, 0.8, pl->afEdge);
    if (pl->bPopped) pl->fLine = 2.5;
    if (pl->bPopped) IOSTouch_Grey(IOSTouch_DarkReads(pl->afFill) ? 0.08 : 1.0, 1.0, pl->afText);
    else IOSTouch_Grey(1.0, 1.0, pl->afText);
  }
  else if (pl->iState == WSTATE_NOAMMO) {
    pl->iIcon = WICON_NOAMMO;
    IOSTouch_WheelMix(sl->iColour, 0.22, pl->afFill);
    IOSTouch_WheelMix(sl->iColour, pl->bHot ? 0.8 : 0.55, pl->afEdge);
    if (pl->bHot) pl->fLine = 2.5;
    IOSTouch_Grey(1.0, 0.75, pl->afText);
  }
  else {
    pl->iIcon = WICON_NOTFOUND;
    IOSTouch_Grey(pl->bHot ? 0.24 : 0.18, 0.92, pl->afFill);
    IOSTouch_WheelMix(sl->iColour, pl->bHot ? 0.7 : 0.45, pl->afEdge);
    if (pl->bHot) pl->fLine = 2.5;
    IOSTouch_Grey(pl->bHot ? 0.75 : 0.59, 1.0, pl->afText);
    pl->iCount = -1;
  }
  if (pl->bWanted) {
    IOSTouch_Grey(1.0, 1.0, pl->afEdge);
    pl->fLine = 2.5;
  }
}

// The needle at the edge of the middle, the way the sliding thumb points:
// whether it shows, its ends (points) and colour
static int IOSTouch_WheelNeedle(double *px0, double *py0, double *px1, double *py1, float af[4])
{
  const IOSTouchSlot *pSlide = NULL;
  const int hot = IOSTouch_WheelPointed(NULL, &pSlide);
  if (!pSlide || !pSlide->bArmed || hot == -1) return 0;
  const double a = pSlide->wheelAim * M_PI / 180.0;
  *px0 = _fWheelCX + (_fWheelR0 - 9.0) * cos(a);
  *py0 = _fWheelCY - (_fWheelR0 - 9.0) * sin(a);
  *px1 = _fWheelCX + (_fWheelR0 - 2.0) * cos(a);
  *py1 = _fWheelCY - (_fWheelR0 - 2.0) * sin(a);
  if (hot >= 0 && IOSTouch_WheelSlotState(hot) == WSTATE_READY) IOSTouch_WheelMix(IOSTouch_WheelMapOf(_iWheelMap)->aSlots[hot].iColour, 1.0, af);
  else IOSTouch_Grey(0.6, 1.0, af);
  return 1;
}

// A finger came down at (x,y) on a screen W points wide; now: when it
// reached us (as IOSTouch_TickHolds counts), tTouch: when it went down by
// the touch's own clock
static void IOSTouch_TouchBegan(const void *touch, double x, double y, double W, double now, double tTouch)
{
  IOSTouchSlot *s = IOSTouch_FindSlot(NULL);
  if (!s || !touch) return;
  memset(s, 0, sizeof(*s));
  s->touch = touch;
  s->x = x;
  s->y = y;
  s->tDown = now;
  s->tDownTouch = tTouch;
  s->uSeq = ++_uTouchSeq;
  s->trayButton = -1;
  s->wheelSlot = -1;
  // The open weapon wheel takes every touch: on a slice it is a tap there,
  // anywhere else it closes the wheel as it lifts
  if (_bWheelOpen) {
    s->role = ROLE_WHEEL;
    s->button = -1;
    s->wheelSlot = IOSTouch_WheelSliceAt(x, y, -1);
    IOSTouch_WheelUpdateHot();
    return;
  }
  s->button = IOSTouch_ButtonAt(x, y);

  // An open tray closes at a touch anywhere else, which then does what it
  // would anyway -- except on MENU, where it only closes the tray
  if (_bTrayOpen && !IOSTouch_IsTrayButton(s->button)) {
    IOSTouch_SetTrayOpen(0);
    if (s->button == BTN_MENU) {
      s->role = ROLE_IGNORED;
      return;
    }
  }

  if (s->button >= 0 && _aButtons[s->button].kind == KIND_WHEEL) {
    // NEXT WPN, PREV WPN: nothing yet -- a tap, a slide or a hold
    // (IOSTouch_TouchMoved, IOSTouch_TickHolds, IOSTouch_TouchEnded). A
    // second finger on the same button is ignored.
    int bOther = 0;
    for (int k = 0; k < IOSTOUCH_MAX_TOUCHES; k++) {
      const IOSTouchSlot *o = &_aSlots[k];
      if (o != s && IOSTouch_IsWheelPress(o) && o->button == s->button) bOther = 1;
    }
    if (bOther) {
      s->role = ROLE_IGNORED;
    }
    else {
      s->role = ROLE_BUTTON;
      _aButtonHeld[s->button]++;
      s->xDown = x;
      s->yDown = y;
    }
  }
  else if (s->button >= 0) {
    s->role = ROLE_BUTTON;
    _aButtonHeld[s->button]++;
  }
  else if (IOSTouch_IsOnMessages(x, y)) {
    s->role = ROLE_MESSAGES; // neither moves nor looks; the box does its thing as the finger lifts or holds on
    s->xDown = x;
    s->yDown = y;
    s->rLaidDown = _rMessages;
    s->rNowDown = _rMessagesNow;
  }
  else if (_iMode != IOSTOUCH_GAMEPLAY) {
    s->role = ROLE_IGNORED; // only the buttons are live (console open, paused)
  }
  else if (x < W * IOSTOUCH_STICK_ZONE && !_bStickActive) {
    s->role = ROLE_STICK;
    _bStickActive = 1;
    _fStickOriginX = x;
    _fStickOriginY = y;
    _fStickX = _fStickY = 0.0f;
  }
  else {
    s->role = ROLE_LOOK;
  }
  IOSTouch_SetHeld(IOSTouch_HeldButtons(), 0);
}

// A finger moved to (x,y). Returns whether the buttons' looks changed (a
// thumb held on MENU slid onto or off a tray button, the weapon wheel opened).
static int IOSTouch_TouchMoved(const void *touch, double x, double y)
{
  IOSTouchSlot *s = touch ? IOSTouch_FindSlot(touch) : NULL;
  if (!s) return 0;
  int bLooksChanged = 0;
  // NEXT WPN, PREV WPN slid far enough from where they went down: the
  // weapon wheel opens at once, to slide to a slice (from here on this is
  // its opener)
  if (IOSTouch_WheelPressSlid(s, x, y)) bLooksChanged = 1;
  if (s->role == ROLE_WHEEL) {
    if (s->bWheelOpener && s->bWheelHeld) {
      // opened by holding still: open to tap, until it slides out of the
      // dead zone -- then it picks by sliding
      if (hypot(x - s->xDown, y - s->yDown) >= IOSTOUCH_WHEEL_DEAD) {
        _bWheelTapMode = 0;
        s->bWheelHeld = 0;
        IOSTouch_WheelAim(s, x, y);
      }
    }
    else if (s->bWheelOpener && !_bWheelTapMode) {
      IOSTouch_WheelAim(s, x, y);
    }
    else {
      s->wheelSlot = IOSTouch_WheelSliceAt(x, y, s->wheelSlot);
    }
    IOSTouch_WheelUpdateHot();
  }
  else if (s->role == ROLE_BUTTON && s->button == BTN_MENU && s->bFired && _bTrayOpen) {
    // Held until the tray opened: the tray button under the thumb lights up
    int tb = IOSTouch_ButtonAt(x, y);
    tb = IOSTouch_IsTrayButton(tb) ? tb : -1;
    if (tb != s->trayButton) {
      s->trayButton = tb;
      bLooksChanged = 1;
    }
  }
  else if (s->role == ROLE_STICK) {
    float dx = (float)(x - _fStickOriginX) / IOSTOUCH_STICK_RADIUS;
    float dy = (float)(y - _fStickOriginY) / IOSTOUCH_STICK_RADIUS;
    float len = sqrtf(dx * dx + dy * dy);
    if (len > 1.0f) { dx /= len; dy /= len; }
    _fStickX = dx;
    _fStickY = dy;
    IOSTouch_SetMoveFromStick();
  }
  else if (s->role == ROLE_LOOK || (s->role == ROLE_BUTTON && _aButtons[s->button].bLookWhileHeld)) {
    const float fLookX = (float)(x - s->x) * IOSTOUCH_LOOK_SCALE_X;
    const float fLookY = (float)(y - s->y) * IOSTOUCH_LOOK_SCALE_Y;
    os_unfair_lock_lock(&_lock);
    if (_bReading) {
      _fLookX += fLookX;
      _fLookY += fLookY;
    }
    os_unfair_lock_unlock(&_lock);
  }
  // QUICK SAVE, QUICK LOAD: a finger that leaves the button, even between two
  // frames, doesn't save or load, even if it comes back on (IOSTouch_TickHolds
  // checks too, for a button that moved away from a finger keeping still)
  if (s->role == ROLE_BUTTON && IOSTouch_IsQuickHold(s->button) && !IOSTouch_IsOnButton(x, y, s->button)) {
    s->bFired = 1;
  }
  // The unread messages box: as those, a finger that leaves it neither marks
  // the messages read nor opens NETRICSA, even if it comes back on
  if (s->role == ROLE_MESSAGES && !IOSTouch_StillOnMessages(s, x, y)) {
    s->bFired = 1;
  }
  s->x = x;
  s->y = y;
  return bLooksChanged;
}

// A finger passed (x,y) on its way to where IOSTouch_TouchMoved is told it
// went next (UIKit merges a finger's moves while the game's frame runs, and
// keeps the places in between): only QUICK SAVE, QUICK LOAD and the unread
// messages box care, so a slide off one and back on still ends its hold
static void IOSTouch_TouchPassed(const void *touch, double x, double y)
{
  IOSTouchSlot *s = touch ? IOSTouch_FindSlot(touch) : NULL;
  // (NEXT WPN and PREV WPN too: a slide that far opens the wheel, even if it
  // came back)
  if (s) IOSTouch_WheelPressSlid(s, x, y);
  if (s && s->role == ROLE_BUTTON && IOSTouch_IsQuickHold(s->button) && !IOSTouch_IsOnButton(x, y, s->button)) {
    s->bFired = 1;
  }
  if (s && s->role == ROLE_MESSAGES && !IOSTouch_StillOnMessages(s, x, y)) {
    s->bFired = 1;
  }
}

// A finger lifted at (x,y), at tTouch by its own clock. bCancelled: iOS
// took the touch away (a call, a system gesture...) -- release whatever it
// held, but don't treat it as a finished tap.
static void IOSTouch_TouchEnded(const void *touch, double x, double y, int bCancelled, double tTouch)
{
  IOSTouchSlot *s = touch ? IOSTouch_FindSlot(touch) : NULL;
  if (!s) return;
  unsigned int ulLifted = 0;
  if (s->role == ROLE_WHEEL && _bWheelOpen) {
    if (bCancelled) {
      // the opener taken away: the wheel stays open, to tap
      if (s->bWheelOpener) _bWheelTapMode = 1;
    }
    else if (s->bWheelOpener && s->bWheelHeld) {
      // opened by holding still, lifted without sliding: it stays open, to tap
    }
    else if (s->bWheelOpener && !_bWheelTapMode) {
      // the slide's lift: what it points at, or no change -- or, if it never
      // slid out of the dead zone, the wheel stays open to tap
      IOSTouch_WheelAim(s, x, y);
      if (!s->bArmed) _bWheelTapMode = 1;
      else IOSTouch_WheelClose(s->wheelSlot);
    }
    else {
      // A tap: on a weapon it can switch to picks it; on one it can't the
      // wheel stays open; anywhere else (the weapon in hand, the middle, the
      // gap, off the ring, a button) it closes with no change -- except off
      // the ring while the opener is still sliding and pointing: that finger
      // is only resting, the slide goes on
      const int slice = IOSTouch_WheelSliceAt(x, y, s->wheelSlot);
      int bSliding = 0;
      for (int k = 0; k < IOSTOUCH_MAX_TOUCHES; k++) {
        const IOSTouchSlot *o = &_aSlots[k];
        if (o != s && o->touch && o->role == ROLE_WHEEL && o->bWheelOpener && o->bArmed && !_bWheelTapMode) bSliding = 1;
      }
      if (!(slice == -1 && bSliding) && !(slice >= 0 && IOSTouch_WheelSlotState(slice) != WSTATE_READY)) {
        IOSTouch_WheelClose(slice);
      }
    }
  }
  else if (IOSTouch_IsWheelPress(s)) {
    // NEXT WPN, PREV WPN lifted before the wheel opened
    const IOSTouchButton *b = &_aButtons[s->button];
    if (_aButtonHeld[s->button] > 0) _aButtonHeld[s->button]--;
    _afWheelRing[s->button == BTN_PREVWPN] = 0.0f;
    if (bCancelled || s->bFired) {
      // iOS took it, or it slid or held while the wheel couldn't open: nothing
    }
    else if (hypot(x - s->xDown, y - s->yDown) >= IOSTOUCH_WHEEL_OPEN_SLIDE) {
      // a flick, with no move in between: as a slide, then its lift
      if (IOSTouch_WheelCanOpen()) {
        IOSTouch_WheelOpen(s, 0);
        IOSTouch_WheelAim(s, x, y);
        if (s->bArmed) IOSTouch_WheelClose(s->wheelSlot);
        else _bWheelTapMode = 1;
      }
    }
    else if (tTouch - s->tDownTouch < IOSTOUCH_WHEEL_HOLD) {
      // a quick tap (by the touch's own clock, so a slow frame between the
      // two doesn't make it long): one press of NEXT / PREV
      ulLifted |= b->ulAction;
    }
    else if (IOSTouch_WheelCanOpen()) {
      // held long enough, but lifted before a frame could see it (a slow
      // one): the hold, the wheel open to tap
      IOSTouch_WheelOpen(s, 1);
    }
  }
  else if (s->role == ROLE_BUTTON) {
    const IOSTouchButton *b = &_aButtons[s->button];
    if (_aButtonHeld[s->button] > 0) _aButtonHeld[s->button]--;
    // A tap so quick that no game tick saw it held still counts as one press
    if (!bCancelled && b->kind == KIND_HOLD && _aButtonHeld[s->button] == 0) {
      ulLifted |= b->ulAction;
    }
    // These act when the finger lifts on the button, so a slip onto one can
    // be dragged off again
    if (!bCancelled && IOSTouch_LiftsOnButton(x, y, s->button)) {
      if (b->kind == KIND_TAP) {
        _iRequests |= b->ulAction;
      }
      else if (b->kind == KIND_PRESS) {
        ulLifted |= b->ulAction; // never held, so the game gets it as one press
      }
      else if (IOSTouch_IsTrayButton(s->button)) {
        IOSTouch_UseTrayButton(s->button);
      }
      else if (b->kind == KIND_MENU && !s->bFired) {
        _iRequests |= b->ulAction; // a tap: the menu
      }
    }
    // MENU held until its tray opened, then slid onto one of its buttons
    if (!bCancelled && s->button == BTN_MENU && s->bFired && _bTrayOpen) {
      const int tb = IOSTouch_ButtonAt(x, y);
      if (IOSTouch_IsTrayButton(tb)) IOSTouch_UseTrayButton(tb);
    }
    // a lift never saves or loads: only a finished hold does
    if (s->button == BTN_QUICKSAVE) _fSaveRing = 0.0f;
    if (s->button == BTN_QUICKLOAD) _fLoadRing = 0.0f;
    if (s->button == BTN_MENU) _fMenuRing = 0.0f;
  }
  else if (s->role == ROLE_MESSAGES) {
    // A tap -- lifted on the box before its hold opened NETRICSA, without
    // having left it: every message read (once the main loop gets to it).
    // With nothing unread (the box dim) a tap does nothing.
    if (!bCancelled && !s->bFired && IOSTouch_StillOnMessages(s, x, y) && _hud.ctMessages > 0) {
      _iRequests |= IOSTOUCH_REQ_READMESSAGES;
    }
    _fMessagesRing = 0.0f;
  }
  else if (s->role == ROLE_STICK) {
    _bStickActive = 0;
    _fStickX = _fStickY = 0.0f;
    IOSTouch_SetMoveFromStick();
  }
  memset(s, 0, sizeof(*s));
  if (_bWheelOpen) IOSTouch_WheelUpdateHot();
  IOSTouch_SetHeld(IOSTouch_HeldButtons(), ulLifted);
}

// Once per frame while shown: the QUICK SAVE, QUICK LOAD and MENU holds, and
// the unread messages box's
static void IOSTouch_TickHolds(double now)
{
  // QUICK SAVE and QUICK LOAD go off only once the finger is known to have
  // stayed down long enough, so they are timed to the previous tick, not this
  // one. UIKit hands over touches whenever SDL pumps events: in the frame's
  // message loop and right after each swap (GfxLibrary.cpp), so every frame
  // the game draws pumps between two ticks. By now, then, every lift made
  // before the previous tick has arrived: a finger still down was down from
  // tDown to then. This costs at most a frame.
  const double known = _tLastTick;
  _tLastTick = now;
  // NEXT WPN and PREV WPN held still (they haven't slid, or the wheel would
  // be open): known to be held IOSTOUCH_WHEEL_HOLD, the wheel opens to tap a
  // slice; until then the ring fills. The first to get there opens it (which
  // drops the other). This comes before the QUICK SAVE, QUICK LOAD, MENU and
  // messages box holds: one that completes in the same tick is then dropped
  // by the wheel opening, which ignores every other touch, rather than saving
  // or loading under the wheel. While the wheel couldn't open (the player
  // dead...) there is no ring, and a press held that long is no tap either.
  float afWheelRing[2] = { 0.0f, 0.0f };
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES && !_bWheelOpen; i++) {
    IOSTouchSlot *s = &_aSlots[i];
    if (!IOSTouch_IsWheelPress(s) || s->bFired) continue;
    if (known - s->tDown >= IOSTOUCH_WHEEL_HOLD) {
      if (IOSTouch_WheelCanOpen()) {
        IOSTouch_WheelOpen(s, 1);
        afWheelRing[0] = afWheelRing[1] = 0.0f;
        break; // (every other touch is ignored now)
      }
      s->bFired = 1;
      continue;
    }
    if (IOSTouch_WheelCanOpen()) {
      float *pf = &afWheelRing[s->button == BTN_PREVWPN];
      *pf = fmaxf(*pf, (float)fmax(0.0, (known - s->tDown) / IOSTOUCH_WHEEL_HOLD));
    }
  }
  _afWheelRing[0] = afWheelRing[0];
  _afWheelRing[1] = afWheelRing[1];
  // the furthest along of QUICK SAVE's and of QUICK LOAD's holds (a touch each)
  float fSaveRing = 0.0f, fLoadRing = 0.0f, fMessagesRing = 0.0f;
  int iDone = -1; // the quick hold that completed: BTN_QUICKSAVE or BTN_QUICKLOAD
  int bMessagesDone = 0; // a hold on the unread messages box completed
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    IOSTouchSlot *s = &_aSlots[i];
    if (!s->touch || s->bFired) continue;
    if (s->role == ROLE_MESSAGES) {
      if (!IOSTouch_StillOnMessages(s, s->x, s->y)) {
        // the box went away under the finger (the HUD stopped drawing it) or
        // was laid out somewhere else: this touch does nothing more
        s->bFired = 1;
        continue;
      }
      // done once the finger is known to have stayed on long enough, as QUICK
      // SAVE's hold. The ring shows that too, so it is only ever full when
      // NETRICSA opens: a lift a moment after it looked full must not be
      // taken for a tap, which marks the messages read instead (QUICK SAVE's
      // ring, where that lift just does nothing, shows the time down).
      if (known - s->tDown >= IOSTOUCH_MESSAGES_HOLD) bMessagesDone = 1;
      else fMessagesRing = fmaxf(fMessagesRing, (float)fmax(0.0, (known - s->tDown) / IOSTOUCH_MESSAGES_HOLD));
      continue;
    }
    if (s->role != ROLE_BUTTON) continue;
    if (IOSTouch_IsQuickHold(s->button)) {
      if (!IOSTouch_IsOnButton(s->x, s->y, s->button)) {
        // off it (a finger that slid off is already done, in
        // IOSTouch_TouchMoved; this is the button laid out again away from a
        // finger keeping still): this touch doesn't save or load, even if it
        // comes back on
        s->bFired = 1;
        continue;
      }
      const double hold = (s->button == BTN_QUICKSAVE) ? IOSTOUCH_QUICKSAVE_HOLD : IOSTOUCH_QUICKLOAD_HOLD;
      if (known - s->tDown >= hold) {
        // the ring is full, with the finger still on it. QUICK SAVE and QUICK
        // LOAD both found done in the same tick (one long frame can cover
        // both, whichever was touched first): QUICK SAVE, as only a load
        // throws away the game being played
        if (iDone != BTN_QUICKSAVE) iDone = s->button;
      }
      else {
        const float fRing = (float)fmin((now - s->tDown) / hold, 1.0);
        if (s->button == BTN_QUICKSAVE) fSaveRing = fmaxf(fSaveRing, fRing);
        else fLoadRing = fmaxf(fLoadRing, fRing);
      }
    }
    else if (s->button == BTN_MENU) {
      if (!IOSTouch_IsOnButton(s->x, s->y, BTN_MENU)) {
        // slid off: no tray, and no menu either
        s->bFired = 1;
        _fMenuRing = 0.0f;
        continue;
      }
      const double progress = (now - s->tDown) / IOSTOUCH_MENU_HOLD;
      if (progress >= 1.0) {
        s->bFired = 1;
        _fMenuRing = 0.0f;
        IOSTouch_SetTrayOpen(1);
      }
      else {
        _fMenuRing = (float)progress;
      }
    }
  }
  if (iDone >= 0) {
    // One save or load, once: it ends every hold on QUICK SAVE and QUICK LOAD,
    // so two fingers on one button ask once, and the two buttons held together
    // save or load, whichever is found done first, never both (both would only
    // load back the game just saved, or save again the one just loaded)
    for (int j = 0; j < IOSTOUCH_MAX_TOUCHES; j++) {
      IOSTouchSlot *o = &_aSlots[j];
      if (o->touch && o->role == ROLE_BUTTON && IOSTouch_IsQuickHold(o->button)) o->bFired = 1;
    }
    fSaveRing = fLoadRing = 0.0f;
    _iRequests |= _aButtons[iDone].ulAction;
  }
  _fSaveRing = fSaveRing;
  _fLoadRing = fLoadRing;
  if (bMessagesDone) {
    // NETRICSA, once: every hold on the box ends, so two fingers on it ask
    // once. The game gets it as one press of its Computer key (Game.cpp),
    // which opens NETRICSA however the player's USE settings are.
    for (int j = 0; j < IOSTOUCH_MAX_TOUCHES; j++) {
      if (_aSlots[j].touch && _aSlots[j].role == ROLE_MESSAGES) _aSlots[j].bFired = 1;
    }
    fMessagesRing = 0.0f;
    IOSTouch_SetHeld(IOSTouch_HeldButtons(), IOSTOUCH_COMPUTER);
  }
  _fMessagesRing = fMessagesRing;
}

// Once per frame while shown: the FPS readout counts the frames the game
// drew (ulFrames, the game's own count) over IOSTOUCH_FPS_PERIOD or so. It
// starts over whenever the game's count does, and after the overlay was
// hidden (time spent in a menu or loading doesn't count).
static void IOSTouch_CountFrames(unsigned int ulFrames, double now)
{
  if (!_bShowFps) return;
  if (!_bFpsBase || ulFrames < _ulFpsFrames) {
    _bFpsBase = 1;
    _ulFpsFrames = ulFrames;
    _tFpsBase = now;
  }
  else if (now - _tFpsBase >= IOSTOUCH_FPS_PERIOD) {
    _iFpsShown = (int)lround((double)(ulFrames - _ulFpsFrames) / (now - _tFpsBase));
    _ulFpsFrames = ulFrames;
    _tFpsBase = now;
  }
}

// Whether the FPS readout is under the open tray's backing (it keeps clear
// of the FPS and keyboard buttons' part, not of GYRO's and SENS's): it
// hides while the tray is open
static int IOSTouch_FpsUnderTray(void)
{
  const IOSTouchRect *r = &_rTrayBack;
  if (!r->bValid) return 0;
  const double dx = fmax(fmax(r->x0 - (_fFpsX + IOSTOUCH_FPS_W * 0.5), (_fFpsX - IOSTOUCH_FPS_W * 0.5) - r->x1), 0.0);
  const double dy = fmax(fmax(r->y0 - (_fFpsY + IOSTOUCH_FPS_H * 0.5), (_fFpsY - IOSTOUCH_FPS_H * 0.5) - r->y1), 0.0);
  return hypot(dx, dy) < 4.0;
}

// ---------------------------------------------------------------- tilt aiming
// The view starts and stops CoreMotion's updates (IOSTouch_GyroRunUpdates)
// and hands each sample to IOSTouch_GyroSample, on the samples' own queue;
// IOSTouch_GyroFrame runs once a frame on the main thread, after the
// frame's touches came in, and hands what may aim to the game's
// IOSTouch_TakeGyro (either game thread). The two locks are never held
// together.

static void IOSTouch_GyroRunUpdates(int bRun); // the view's (CoreMotion)

// One sample of device motion, on the samples' queue: the rotation rate w
// (rad/s) and gravity g (toward the ground) in the device's own axes (x
// right, y up, z out of the screen, as if held upright), taken at time t.
// Adds how far it turns and tilts the view.
static void IOSTouch_GyroSample(double wx, double wy, double wz, double gx, double gy, double gz, double t)
{
  os_unfair_lock_lock(&_gyroLock);
  const double dt = _tGyroLastSample > 0.0 ? t - _tGyroLastSample : 0.0;
  _tGyroLastSample = t;
  const double s = _iGyroSide;
  const double gn = sqrt(gx * gx + gy * gy + gz * gz);
  if (s != 0.0 && dt > 0.0 && dt <= IOSTOUCH_GYRO_MAX_DT && gn > 0.1) {
    // The screen's axes as the player sees it: right, up, toward them. How
    // fast the phone turns about each (the right-hand way round: + about up
    // turns left), and how far each points up.
    const double rx = s * wy, ry = -s * wx, rz = wz;
    const double ux = -s * gy / gn, uy = s * gx / gn, uz = -gz / gn;
    // Not while held upside down for the way round the screen is turned
    // (rolled more than 120 degrees either way, unless within 30 of flat):
    // the phone is on its way round to the other landscape side
    const double tilt = sqrt(ux * ux + uy * uy);
    if (tilt < 0.5 || uy > -0.5 * tilt) {
      double yaw = ry, pitch = rx;
      if (uz >= 0.0 && (tilt < 0.5 || uy > 0.5 * tilt)) {
        // Player space, while the screen faces up and is held the way round
        // it is turned (rolled less than 60 degrees either way) or about
        // flat: turning is about up, from the screen's up and
        // toward-the-player axes as far as each points up
        yaw = uy * ry + uz * rz;
        const double mag = sqrt(ry * ry + rz * rz);
        yaw = copysign(fmin(fabs(yaw) * IOSTOUCH_GYRO_YAW_RELAX, mag), yaw);
      }
      // (Otherwise local space: facing down, or rolled further over --
      // which also leaves out the roll of a phone on its way round.)
      yaw *= 180.0 / M_PI;
      pitch *= 180.0 / M_PI;

      // Smoothed only where it is slow
      double m = sqrt(yaw * yaw + pitch * pitch);
      double direct = (m - IOSTOUCH_GYRO_SMOOTH * 0.5) / (IOSTOUCH_GYRO_SMOOTH * 0.5);
      direct = direct < 0.0 ? 0.0 : (direct > 1.0 ? 1.0 : direct);
      _afGyroSmooth[_iGyroSmoothNext][0] = yaw * (1.0 - direct);
      _afGyroSmooth[_iGyroSmoothNext][1] = pitch * (1.0 - direct);
      _iGyroSmoothNext = (_iGyroSmoothNext + 1) % IOSTOUCH_GYRO_SMOOTH_N;
      double sumYaw = 0.0, sumPitch = 0.0;
      for (int i = 0; i < IOSTOUCH_GYRO_SMOOTH_N; i++) {
        sumYaw += _afGyroSmooth[i][0];
        sumPitch += _afGyroSmooth[i][1];
      }
      yaw = yaw * direct + sumYaw / IOSTOUCH_GYRO_SMOOTH_N;
      pitch = pitch * direct + sumPitch / IOSTOUCH_GYRO_SMOOTH_N;

      // The soft dead zone
      m = sqrt(yaw * yaw + pitch * pitch);
      if (m < IOSTOUCH_GYRO_SOFT) {
        yaw *= m / IOSTOUCH_GYRO_SOFT;
        pitch *= m / IOSTOUCH_GYRO_SOFT;
      }
      _fGyroQueueYaw += yaw * dt;
      _fGyroQueuePitch += pitch * dt;
    }
  }
  os_unfair_lock_unlock(&_gyroLock);
}

// A sample came back refused (the samples' queue): no tilt aiming from the
// next frame on
static void IOSTouch_GyroRefusedOnQueue(void)
{
  os_unfair_lock_lock(&_gyroLock);
  _bGyroRefusedOnQueue = 1;
  os_unfair_lock_unlock(&_gyroLock);
}

// Starts or stops the motion updates
static void IOSTouch_GyroRun(int bRun)
{
  bRun = bRun != 0;
  if (bRun == _bGyroRunning) return;
  _bGyroRunning = bRun;
  if (!bRun) {
    IOSTouch_GyroRunUpdates(0);
    return;
  }
  // From scratch: nothing from before it stopped, the smoothing empty
  os_unfair_lock_lock(&_gyroLock);
  _tGyroLastSample = 0.0;
  _fGyroQueueYaw = _fGyroQueuePitch = 0.0;
  memset(_afGyroSmooth, 0, sizeof(_afGyroSmooth));
  os_unfair_lock_unlock(&_gyroLock);
  IOSTouch_GyroRunUpdates(1);
}

// Whether either thumb is down on the game, for TOUCH: the left one on the
// move stick (pushed or resting), or a right one where it aims -- on the
// look area (resting or dragging), or on one of the buttons a drag on also
// looks (FIRE, ZOOM, CROUCH, USE, JUMP). So with the left thumb on the
// stick, the right one can hop from the look area onto FIRE (and is in the
// air for a moment) without the aiming stopping. Not BOMB, the top row,
// the unread messages box, the tray, or a touch being ignored.
static int IOSTouch_GyroThumbDown(void)
{
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    const IOSTouchSlot *s = &_aSlots[i];
    if (!s->touch) continue;
    if (s->role == ROLE_STICK || s->role == ROLE_LOOK
        || (s->role == ROLE_BUTTON && _aButtons[s->button].bLookWhileHeld)) return 1;
  }
  return 0;
}

// Once per frame, after the frame's touches came in (bShown: whether the
// overlay is up; bActive: whether the app is in front; side: which way round
// the screen is turned, +1 landscape left, -1 landscape right, 0 neither).
// The motion updates run only while the game is being played with the
// overlay up, the app in front, tilt aiming on and the screen turned either
// landscape way. What the phone turned since the last frame goes to the
// game, for the player's rotation (IOSTouch_TakeGyro) -- if it could aim
// both then and now, so in TOUCH lifting the last thumb freezes the view
// where it is (the frame it lifted in counts for nothing, as does the frame
// the first one lands in) and nothing springs back, and touching again
// carries on from there, from however the phone is held by then. Never
// while MENU's tray or the weapon wheel is open (the frame it closes in
// counts for nothing either, so nothing jumps), just after the screen turned round to the
// other landscape side, nor after a frame that took too long; and only
// while the game reads the touch controls, so nothing is left waiting for
// it across a pause.
static void IOSTouch_GyroFrame(int bShown, int bActive, int side, double now)
{
  if (side != 0 && _iGyroLastSide != 0 && side != _iGyroLastSide) _tGyroTurnedRound = now;
  if (side != 0) _iGyroLastSide = side;
  IOSTouch_GyroRun(bShown && _iMode == IOSTOUCH_GAMEPLAY && bActive && side != 0 && _iGyroMode != IOSTOUCH_GYRO_OFF
                   && IOSTouch_GyroAvailable());

  os_unfair_lock_lock(&_gyroLock);
  _iGyroSide = side;
  const double yaw = _fGyroQueueYaw, pitch = _fGyroQueuePitch;
  _fGyroQueueYaw = _fGyroQueuePitch = 0.0;
  _bGyroRefused |= _bGyroRefusedOnQueue; // (stops it next frame)
  os_unfair_lock_unlock(&_gyroLock);

  const int bOk = _bGyroRunning && (_iGyroMode == IOSTOUCH_GYRO_ALWAYS || IOSTouch_GyroThumbDown()) && !_bTrayOpen
                  && now - _tGyroTurnedRound >= IOSTOUCH_GYRO_TURN_HOLD && !IOSTouch_WheelIsOpen();
  const int bUse = bOk && _bGyroWasOk && now - _tGyroLastFrame <= IOSTOUCH_GYRO_MAX_FRAME;
  _bGyroWasOk = bOk;
  _tGyroLastFrame = now;
  if (!bUse) return;

  // Degrees, straight into the player's rotation (Game.cpp): the game's
  // mouse settings never apply, so at 1.0x the view turns as far as the phone
  const float k = _afGyroSens[_iGyroSens];
  os_unfair_lock_lock(&_lock);
  if (_bReading) {
    _fGyroYaw += (float)yaw * k;
    _fGyroPitch += (float)pitch * k;
  }
  os_unfair_lock_unlock(&_lock);
}

// Lets go of every touch and closes the tray and the weapon wheel (on every
// change of mode);
// bReading: whether the game gets input now
static void IOSTouch_ResetTouches(int bReading)
{
  IOSTouch_SetTrayOpen(0);
  memset(_aSlots, 0, sizeof(_aSlots));
  memset(_aButtonHeld, 0, sizeof(_aButtonHeld));
  _bStickActive = 0;
  _fStickX = _fStickY = 0.0f;
  _iRequests = 0;
  _fSaveRing = _fLoadRing = _fMenuRing = _fMessagesRing = 0.0f;
  _tLastTick = 0.0;
  _bFpsBase = 0;
  _bGyroWasOk = 0; // the next frame's motion doesn't count
  // the weapon wheel closes, picking nothing (the game no longer held)
  _bWheelOpen = _bWheelTapMode = 0;
  _iWheelHot = -1;
  _ctWheelTicks = 0;
  _afWheelRing[0] = _afWheelRing[1] = 0.0f;
  IOSTouch_ResetShared(bReading);
}

// ---------------------------------------------------------------- overlay view

// Kept in the app's settings: whether the FPS readout shows; tilt aiming's
// mode (0 OFF, 1 TOUCH, 2 ALWAYS; never set or not one of those: OFF) and
// sensitivity (the nearest of _afGyroSens; never set: 1.5x)
#define IOSTOUCH_FPS_DEFAULTS_KEY @"iosTouchShowFps"
#define IOSTOUCH_GYRO_DEFAULTS_KEY @"iosTouchGyroMode"
#define IOSTOUCH_GYRO_SENS_DEFAULTS_KEY @"iosTouchGyroSens"

// Tilt aiming's motion manager (one for the app, as Apple asks) and the
// queue its samples are handled on
static CMMotionManager *_pMotion = nil;
static NSOperationQueue *_pMotionQueue = nil;

// Whether an error the motion updates hand back is iOS refusing the motion
// data (no permission: none is asked for today, but iOS could start to)
static int IOSTouch_GyroIsRefusal(NSError *err)
{
  if (![err.domain isEqualToString:CMErrorDomain]) return 0;
  return err.code == CMErrorNotAuthorized || err.code == CMErrorNotEntitled
         || err.code == CMErrorMotionActivityNotAuthorized || err.code == CMErrorMotionActivityNotEntitled;
}

// Starts or stops CoreMotion's updates (IOSTouch_GyroRun decides when)
static void IOSTouch_GyroRunUpdates(int bRun)
{
  if (!bRun) {
    [_pMotion stopDeviceMotionUpdates];
    return;
  }
  _pMotion.deviceMotionUpdateInterval = 1.0 / IOSTOUCH_GYRO_HZ;
  // (the reference frame that needs no compass: the attitude isn't used)
  [_pMotion startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical
                                                toQueue:_pMotionQueue
                                            withHandler:^(CMDeviceMotion *dm, NSError *err) {
    if (err && IOSTouch_GyroIsRefusal(err)) IOSTouch_GyroRefusedOnQueue();
    if (!dm || err) return;
    const CMRotationRate w = dm.rotationRate;
    const CMAcceleration g = dm.gravity;
    IOSTouch_GyroSample(w.x, w.y, w.z, g.x, g.y, g.z, dm.timestamp);
  }];
}

// Once, as the overlay is made: the motion manager and the queue for its
// samples (nothing runs yet), and the settings -- OFF and 1.5x unless set
static void IOSTouch_GyroSetup(void)
{
  if (_pMotion) return;
  _pMotion = [[CMMotionManager alloc] init];
  _pMotionQueue = [[NSOperationQueue alloc] init];
  _pMotionQueue.maxConcurrentOperationCount = 1; // in order, one at a time
  _pMotionQueue.qualityOfService = NSQualityOfServiceUserInteractive;
  _bGyroAvailable = _pMotion.deviceMotionAvailable ? 1 : 0;

  NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
  if ([d objectForKey:IOSTOUCH_GYRO_DEFAULTS_KEY]) {
    const NSInteger m = [d integerForKey:IOSTOUCH_GYRO_DEFAULTS_KEY];
    _iGyroMode = (m >= 0 && m < IOSTOUCH_GYRO_NUM_MODES) ? (int)m : IOSTOUCH_GYRO_OFF;
  }
  if ([d objectForKey:IOSTOUCH_GYRO_SENS_DEFAULTS_KEY]) {
    const float k = [d floatForKey:IOSTOUCH_GYRO_SENS_DEFAULTS_KEY];
    for (int i = 0; i < IOSTOUCH_GYRO_NUM_SENS; i++) {
      if (fabsf(_afGyroSens[i] - k) < fabsf(_afGyroSens[_iGyroSens] - k)) _iGyroSens = i;
    }
  }
}

static IOSTouchRect _rScoreFrac, _rHiScoreFrac, _rMessagesFrac; // the last boxes the HUD showed (fractions)
// What the current layout was made for
static IOSTouchRect _rLayoutScore, _rLayoutHiScore, _rLayoutMessages; // in points
static int _iLayoutCutoutRight = -1;
static unsigned int _ulFramesDrawn = 0; // the game's frame count at the last IOSTouch_Update

// Which way round the screen is turned: +1 landscape left (the top of the
// phone on the right), -1 landscape right (the top on the left), 0 neither
// or not known yet. SDL2 makes its window without a scene, so ask SDL (which
// follows the status bar) if there is none: its LANDSCAPE is landscape
// right, LANDSCAPE_FLIPPED landscape left.
static int IOSTouch_ScreenSide(UIView *v)
{
  UIWindowScene *scene = v.window.windowScene;
  if (scene) {
    const UIInterfaceOrientation o = scene.interfaceOrientation;
    return (o == UIInterfaceOrientationLandscapeLeft) ? 1 : ((o == UIInterfaceOrientationLandscapeRight) ? -1 : 0);
  }
  const SDL_DisplayOrientation o = SDL_GetDisplayOrientation(0);
  return (o == SDL_ORIENTATION_LANDSCAPE_FLIPPED) ? 1 : ((o == SDL_ORIENTATION_LANDSCAPE) ? -1 : 0);
}

// Whether the camera cutout may be on the right of the screen. Landscape right
// has the bottom of the phone on the right, so the cutout (at the top) is on
// the left; landscape left puts it on the right. Not known yet: assume it can
// be.
static int IOSTouch_CutoutMayBeRight(UIView *v)
{
  return IOSTouch_ScreenSide(v) != -1;
}

// What the open weapon wheel was last drawn for
typedef struct {
  int iMap;
  double cx, cy, R1;
  int iHot, bCancel, bTapMode, iWanted;
  unsigned int ulOwned, ulReady;
  int bInfinite;
  int aiAmmo[IOSTOUCH_WPN_MAX], aiMax[IOSTOUCH_WPN_MAX];
} IOSTouchWheelKey;

@interface IOSTouchOverlay : UIView {
  UIView *stickBase;
  UIView *stickKnob;
  UILabel *aButtonViews[IOSTOUCH_NUM_BUTTONS];
  CAShapeLayer *saveRing; // QUICK SAVE's hold progress
  CAShapeLayer *loadRing; // QUICK LOAD's
  CAShapeLayer *menuRing; // MENU's
  UIView *messagesBack;   // over the HUD's unread messages box while a finger is on it...
  CAShapeLayer *messagesRing; // ...and its hold's ring, round the box
  UIView *trayBack;       // behind MENU's tray
  UILabel *fpsLabel;      // the FPS readout...
  int iFpsLabel;          // ...the number it says (-1: none yet)
  int bFpsSaved;          // whether the app's settings say it shows
  int ctBombsShown;       // what BOMB's label says (-1: not yet set)
  int iGyroModeSaved;     // tilt aiming's mode and sensitivity as the app's settings have them
  int iGyroSensSaved;
  int iGyroLabels;        // what GYRO's and SENS's labels say (-1: not yet set)
  CAShapeLayer *aWheelRings[2]; // NEXT WPN's and PREV WPN's holds (they open the weapon wheel)
  // The weapon wheel (makeWheel): the dim and its disc, each slice, its icon
  // (twice for the two colts), count and name, the needle, the middle's
  // lines, "cancel"; the haptic tick; the icons as images (each weapon's,
  // for each tint), whether it shows, what it was drawn for
  UIView *wheelView;
  CAShapeLayer *wheelDisc;
  CAShapeLayer *aSliceLayers[IOSTOUCH_WHEEL_MAX];
  CALayer *aIconLayers[IOSTOUCH_WHEEL_MAX][2];
  UILabel *aCountLabels[IOSTOUCH_WHEEL_MAX];
  UILabel *aNameLabels[IOSTOUCH_WHEEL_MAX];
  CAShapeLayer *wheelNeedle;
  UILabel *aMiddleLabels[IOSTOUCH_MIDDLE_LINES];
  UILabel *wheelCancelLabel;
  UISelectionFeedbackGenerator *wheelTick;
  id aIconImages[IOSTOUCH_WPN_MAX][WICON_NUM];
  int bWheelShown;
  int bWheelRebuild;
  int iWheelLifted; // the button lifted above the dim, + 1 (0: none)
  IOSTouchWheelKey wheelKey;
}
- (void)resetAll;
- (void)tick;
- (void)placeMessages;
- (void)refreshButtonLooks;
- (void)refreshStick;
- (void)syncWheel;
@end

@implementation IOSTouchOverlay

static UIView *IOSTouch_MakeCircle(CGFloat radius, CGFloat alpha)
{
  UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, radius * 2, radius * 2)];
  v.backgroundColor = [UIColor colorWithWhite:1.0 alpha:alpha];
  v.layer.cornerRadius = radius;
  v.layer.borderWidth = 1.5;
  v.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
  v.userInteractionEnabled = NO;
  return v;
}

static CGFloat IOSTouch_FontSize(const char *label, CGFloat radius)
{
  if (strchr(label, '\n')) return radius >= 28 ? 10 : 9; // two-line labels
  if (radius < 40 && strlen(label) > 5) return 12;      // CROUCH: stays on one line
  return radius >= 40 ? 16 : (radius >= 25 ? 13 : 10);
}

// SENS's and GYRO's font: condensed (as in the Jedi Knight port) so "ALWAYS"
// fits a circle this small. Before iOS 16 the system font has no condensed
// width, so it is a point smaller instead.
static UIFont *IOSTouch_TrayFont(CGFloat size)
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
  if (@available(iOS 16.0, *)) return [UIFont systemFontOfSize:size weight:UIFontWeightBold width:UIFontWidthCondensed];
#endif
  return [UIFont boldSystemFontOfSize:size - 1];
}

// A ring round a button of radius r that fills (strokeEnd) while it is held
static CAShapeLayer *IOSTouch_MakeHoldRing(CGFloat r)
{
  CAShapeLayer *ring = [CAShapeLayer layer];
  ring.frame = CGRectMake(0, 0, r * 2, r * 2);
  ring.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(r, r) radius:r - 2.5
                                         startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES].CGPath;
  ring.fillColor = [UIColor clearColor].CGColor;
  ring.strokeColor = [UIColor colorWithRed:0.47 green:0.78 blue:1.0 alpha:0.95].CGColor;
  ring.lineWidth = 3.0;
  ring.strokeEnd = 0.0;
  return ring;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.multipleTouchEnabled = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
      const IOSTouchButton *b = &_aButtons[i];
      UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, b->radius * 2, b->radius * 2)];
      l.text = [NSString stringWithUTF8String:b->label];
      l.textAlignment = NSTextAlignmentCenter;
      l.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
      l.font = [UIFont boldSystemFontOfSize:IOSTouch_FontSize(b->label, b->radius)];
      l.numberOfLines = 2;
      l.adjustsFontSizeToFitWidth = YES;
      l.minimumScaleFactor = 0.6;
      l.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.22];
      l.layer.cornerRadius = b->radius;
      l.layer.borderWidth = 1.5;
      l.layer.borderColor = (i == BTN_FIRE) ? [UIColor colorWithRed:1.0 green:0.55 blue:0.45 alpha:0.6].CGColor
                                            : [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
      l.clipsToBounds = YES;
      l.userInteractionEnabled = NO;
      aButtonViews[i] = l;
      [self addSubview:l];
    }

    // Rings that fill while QUICK SAVE, QUICK LOAD and MENU are held. QUICK
    // SAVE's and QUICK LOAD's look the same, and fill as quickly.
    saveRing = IOSTouch_MakeHoldRing(_aButtons[BTN_QUICKSAVE].radius);
    [aButtonViews[BTN_QUICKSAVE].layer addSublayer:saveRing];
    loadRing = IOSTouch_MakeHoldRing(_aButtons[BTN_QUICKLOAD].radius);
    [aButtonViews[BTN_QUICKLOAD].layer addSublayer:loadRing];
    menuRing = IOSTouch_MakeHoldRing(_aButtons[BTN_MENU].radius);
    [aButtonViews[BTN_MENU].layer addSublayer:menuRing];
    // ...and NEXT WPN's and PREV WPN's, held still to open the weapon wheel to tap
    for (int k = 0; k < 2; k++) {
      aWheelRings[k] = IOSTouch_MakeHoldRing(_aButtons[k ? BTN_PREVWPN : BTN_NEXTWPN].radius);
      [aButtonViews[k ? BTN_PREVWPN : BTN_NEXTWPN].layer addSublayer:aWheelRings[k]];
    }

    // The HUD's unread messages box lights up while a finger is on it, and a
    // ring round it fills while it is held (as MENU's): laid out over the box
    messagesBack = [[UIView alloc] initWithFrame:CGRectZero];
    messagesBack.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    messagesBack.layer.cornerRadius = 6.0;
    messagesBack.userInteractionEnabled = NO;
    messagesBack.hidden = YES;
    messagesRing = [CAShapeLayer layer];
    messagesRing.fillColor = [UIColor clearColor].CGColor;
    messagesRing.strokeColor = [UIColor colorWithRed:0.47 green:0.78 blue:1.0 alpha:0.95].CGColor;
    messagesRing.lineWidth = 3.0;
    messagesRing.strokeEnd = 0.0;
    [messagesBack.layer addSublayer:messagesRing];
    [self addSubview:messagesBack];

    // MENU's tray: its buttons on a dark backing, hidden until a hold on
    // MENU opens it. The keyboard button shows the keyboard symbol.
    trayBack = [[UIView alloc] initWithFrame:CGRectZero];
    trayBack.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    trayBack.layer.cornerRadius = 26.0;
    trayBack.layer.borderWidth = 1.5;
    trayBack.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    trayBack.userInteractionEnabled = NO;
    trayBack.hidden = YES;
    [self insertSubview:trayBack belowSubview:aButtonViews[BTN_TRAYSENS]];
    // GYRO and SENS say what they are set to on a second line (labels set
    // in refreshButtonLooks), sized for the longest
    IOSTouch_GyroSetup();
    iGyroModeSaved = _iGyroMode;
    iGyroSensSaved = _iGyroSens;
    iGyroLabels = -1;
    for (int i = BTN_TRAYSENS; i <= BTN_TRAYGYRO; i++) {
      aButtonViews[i].font = IOSTouch_TrayFont(IOSTouch_FontSize("GYRO\nALWAYS", _aButtons[i].radius));
    }
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    UIImage *kb = [UIImage systemImageNamed:@"keyboard" withConfiguration:cfg];
    if (kb) {
      NSTextAttachment *att = [[NSTextAttachment alloc] init];
      att.image = [kb imageWithTintColor:[UIColor colorWithWhite:1.0 alpha:0.85] renderingMode:UIImageRenderingModeAlwaysOriginal];
      aButtonViews[BTN_TRAYKEYS].attributedText = [NSAttributedString attributedStringWithAttachment:att];
    }
    else {
      aButtonViews[BTN_TRAYKEYS].text = @"TYPE";
    }

    // The FPS readout, shown if it was left on
    fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, IOSTOUCH_FPS_W, IOSTOUCH_FPS_H)];
    fpsLabel.textAlignment = NSTextAlignmentCenter;
    fpsLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
    fpsLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    fpsLabel.layer.cornerRadius = 9.0;
    fpsLabel.clipsToBounds = YES;
    fpsLabel.userInteractionEnabled = NO;
    fpsLabel.text = @"-- FPS";
    iFpsLabel = -1;
    bFpsSaved = [[NSUserDefaults standardUserDefaults] boolForKey:IOSTOUCH_FPS_DEFAULTS_KEY] ? 1 : 0;
    IOSTouch_SetShowFps(bFpsSaved);
    fpsLabel.hidden = !_bShowFps;
    [self addSubview:fpsLabel];
    ctBombsShown = -1;

    stickBase = IOSTouch_MakeCircle(IOSTOUCH_STICK_RADIUS, 0.08);
    stickKnob = IOSTouch_MakeCircle(24, 0.30);
    stickBase.hidden = YES;
    stickKnob.hidden = YES;
    [self addSubview:stickBase];
    [self addSubview:stickKnob];

    [self makeWheel];
    [self refreshButtonLooks];
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGRect b = self.bounds;
  const double W = b.size.width, H = b.size.height;
  UIEdgeInsets in = self.safeAreaInsets;

  // The HUD boxes this layout keeps clear of; IOSTouch_Update lays out again
  // whenever they move, or the cutout changes sides
  _rLayoutScore = IOSTouch_RectInPoints(&_rScoreFrac, W, H);
  _rLayoutHiScore = IOSTouch_RectInPoints(&_rHiScoreFrac, W, H);
  _rLayoutMessages = IOSTouch_RectInPoints(&_rMessagesFrac, W, H);
  _iLayoutCutoutRight = IOSTouch_CutoutMayBeRight(self);
  IOSTouch_LayoutButtons(W, H, in.left, in.top, in.right, in.bottom, _iLayoutCutoutRight,
                         &_rLayoutScore, &_rLayoutHiScore, &_rLayoutMessages);

  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    aButtonViews[i].center = CGPointMake(_aButtons[i].x, _aButtons[i].y);
  }
  trayBack.frame = CGRectMake(_rTrayBack.x0, _rTrayBack.y0, _rTrayBack.x1 - _rTrayBack.x0, _rTrayBack.y1 - _rTrayBack.y0);
  fpsLabel.center = CGPointMake(_fFpsX, _fFpsY);

  [self placeMessages];
  // the open weapon wheel round the new middle
  bWheelRebuild = 1;
  if (bWheelShown) [self refreshWheel];
}

// Over the unread messages box where the HUD drew it last (or where it sits),
// a little bigger, with the ring just inside its edge (the box itself is the
// HUD's, drawn by the game)
- (void)placeMessages
{
  const IOSTouchRect *r = _rMessagesNow.bValid ? &_rMessagesNow : &_rMessages;
  if (!r->bValid) return;
  const CGRect rBack = CGRectMake(r->x0 - 3, r->y0 - 3, r->x1 - r->x0 + 6, r->y1 - r->y0 + 6);
  if (CGRectEqualToRect(messagesBack.frame, rBack)) return;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  messagesBack.frame = rBack;
  messagesRing.frame = messagesBack.bounds;
  messagesRing.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(messagesBack.bounds, 1.5, 1.5) cornerRadius:5.0].CGPath;
  [CATransaction commit];
}

- (void)setRing:(CAShapeLayer *)ring progress:(CGFloat)progress
{
  if (ring.strokeEnd == progress) return;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  ring.strokeEnd = progress;
  [CATransaction commit];
}

// The stick under the left thumb, while it is down
- (void)refreshStick
{
  if (!_bStickActive) {
    stickBase.hidden = YES;
    stickKnob.hidden = YES;
    return;
  }
  stickBase.center = CGPointMake(_fStickOriginX, _fStickOriginY);
  stickKnob.center = CGPointMake(_fStickOriginX + _fStickX * IOSTOUCH_STICK_RADIUS,
                                 _fStickOriginY + _fStickY * IOSTOUCH_STICK_RADIUS);
  stickBase.hidden = NO;
  stickKnob.hidden = NO;
}

// What the tray's GYRO and SENS say: the mode and the sensitivity (NO GYRO
// without one)
- (void)refreshGyroLabels
{
  static const char *const astrMode[IOSTOUCH_GYRO_NUM_MODES] = { "OFF", "TOUCH", "ALWAYS" };
  const int bGyro = IOSTouch_GyroAvailable();
  const int iLabels = (bGyro ? 1 : 0) + 2 * (_iGyroMode + IOSTOUCH_GYRO_NUM_MODES * _iGyroSens);
  if (iLabels == iGyroLabels) return;
  iGyroLabels = iLabels;
  aButtonViews[BTN_TRAYGYRO].text = bGyro ? [NSString stringWithFormat:@"GYRO\n%s", astrMode[_iGyroMode]] : @"NO\nGYRO";
  aButtonViews[BTN_TRAYSENS].text = [NSString stringWithFormat:@"SENS\n%.1fx", (double)_afGyroSens[_iGyroSens]];
}

// Which buttons show and how; the tray and the FPS readout
- (void)refreshButtonLooks
{
  [self refreshGyroLabels];
  const int bGyro = IOSTouch_GyroAvailable();
  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    UILabel *l = aButtonViews[i];
    const int bShown = IOSTouch_IsShown(i);
    if (l.hidden == bShown) l.hidden = !bShown;
    int bHeld = _aButtonHeld[i] != 0 || (_bWheelOpen && i == _iWheelButton); // (the weapon wheel's opener, lit)
    // A thumb still on MENU after its tray opened lights the tray button it is over
    for (int t = 0; t < IOSTOUCH_MAX_TOUCHES && !bHeld; t++) {
      const IOSTouchSlot *s = &_aSlots[t];
      bHeld = s->touch && s->role == ROLE_BUTTON && s->button == BTN_MENU && s->bFired && s->trayButton == i;
    }
    l.backgroundColor = [UIColor colorWithWhite:(bHeld ? 1.0 : 0.0) alpha:(bHeld ? 0.30 : 0.22)];
    // The open console (on MENU and the tray's keyboard), the FPS readout
    // being on (on the tray's FPS) and tilt aiming being on (on the tray's
    // GYRO) stand out in yellow, at full strength
    const int bOn = ((i == BTN_TRAYKEYS || i == BTN_MENU) && _iMode == IOSTOUCH_CONSOLE)
                    || (i == BTN_TRAYFPS && _bShowFps)
                    || (i == BTN_TRAYGYRO && bGyro && _iGyroMode != IOSTOUCH_GYRO_OFF);
    const int bTray = IOSTouch_IsTrayButton(i); // only there while the tray is open
    CGFloat alpha = (bHeld || bOn || bTray) ? 1.0 : IOSTOUCH_IDLE_ALPHA;
    if (i == BTN_TRAYGYRO && !bGyro) alpha *= 0.45;                                       // no gyro here
    if (i == BTN_TRAYSENS && (!bGyro || _iGyroMode == IOSTOUCH_GYRO_OFF)) alpha *= 0.45; // ...or it's off
    l.alpha = alpha;
    if (i != BTN_FIRE) {
      l.layer.borderColor = bOn ? [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:0.95].CGColor
                                : [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    }
  }
  if (trayBack.hidden == _bTrayOpen) trayBack.hidden = !_bTrayOpen;

  // The FPS readout (not while the open tray lies over it), and the app's
  // settings when it, or tilt aiming's mode or sensitivity, was changed
  const int bFpsShown = _bShowFps && !(_bTrayOpen && IOSTouch_FpsUnderTray());
  if (fpsLabel.hidden == bFpsShown) fpsLabel.hidden = !bFpsShown;
  if (bFpsSaved != _bShowFps) {
    bFpsSaved = _bShowFps;
    [[NSUserDefaults standardUserDefaults] setBool:(_bShowFps ? YES : NO) forKey:IOSTOUCH_FPS_DEFAULTS_KEY];
  }
  if (iGyroModeSaved != _iGyroMode) {
    iGyroModeSaved = _iGyroMode;
    [[NSUserDefaults standardUserDefaults] setInteger:_iGyroMode forKey:IOSTOUCH_GYRO_DEFAULTS_KEY];
  }
  if (iGyroSensSaved != _iGyroSens) {
    iGyroSensSaved = _iGyroSens;
    [[NSUserDefaults standardUserDefaults] setFloat:_afGyroSens[_iGyroSens] forKey:IOSTOUCH_GYRO_SENS_DEFAULTS_KEY];
  }
  if (iFpsLabel != _iFpsShown) {
    iFpsLabel = _iFpsShown;
    fpsLabel.text = (_iFpsShown < 0) ? @"-- FPS" : [NSString stringWithFormat:@"%d FPS", _iFpsShown];
  }
}

// The unread messages box lit while a finger that can still tap or hold it is on it
- (void)refreshMessages
{
  int bOn = 0;
  for (int t = 0; t < IOSTOUCH_MAX_TOUCHES && !bOn; t++) {
    bOn = _aSlots[t].touch && _aSlots[t].role == ROLE_MESSAGES && !_aSlots[t].bFired;
  }
  bOn = bOn && IOSTouch_MessagesShown();
  if (bOn) [self placeMessages];
  if (messagesBack.hidden == bOn) messagesBack.hidden = !bOn;
  [self setRing:messagesRing progress:_fMessagesRing];
}

- (void)refreshAll
{
  [self refreshButtonLooks];
  [self refreshStick];
  [self setRing:saveRing progress:_fSaveRing];
  [self setRing:loadRing progress:_fLoadRing];
  [self setRing:menuRing progress:_fMenuRing];
  [self setRing:aWheelRings[0] progress:_afWheelRing[0]];
  [self setRing:aWheelRings[1] progress:_afWheelRing[1]];
  [self refreshMessages];
  [self syncWheel];
}

// ------------------------------------------------------------ weapon wheel

// The middle's fonts (IOSTouch_WheelMiddleLayout measures with these)
static UIFont *IOSTouch_MiddleFont(int iKind, CGFloat size)
{
  if (iKind == WLINE_TITLE) return [UIFont boldSystemFontOfSize:size];
  return [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
}

static double IOSTouch_MiddleTextWidth(const char *str, int iKind, double fSize, void *pUser)
{
  (void)pUser;
  NSString *s = [NSString stringWithUTF8String:str];
  return [s sizeWithAttributes:@{ NSFontAttributeName : IOSTouch_MiddleFont(iKind, fSize) }].width;
}

static UIColor *IOSTouch_Colour(const float af[4])
{
  return [UIColor colorWithRed:af[0] green:af[1] blue:af[2] alpha:af[3]];
}

// A slice's shape: from deg0 round to deg1 (counter-clockwise), radius r0 to r1
static UIBezierPath *IOSTouch_WedgePath(CGPoint c, CGFloat deg0, CGFloat deg1, CGFloat r0, CGFloat r1)
{
  // UIKit's angles go clockwise (y points down)
  const CGFloat a0 = -deg1 * M_PI / 180.0, a1 = -deg0 * M_PI / 180.0;
  UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:c radius:r1 startAngle:a0 endAngle:a1 clockwise:YES];
  [p addArcWithCenter:c radius:r0 startAngle:a1 endAngle:a0 clockwise:NO];
  [p closePath];
  return p;
}

// An icon (RGBA, not premultiplied) as an image; its owner releases it
static CGImageRef IOSTouch_MakeIconImage(const unsigned char *pub, int w, int h)
{
  CFDataRef data = CFDataCreate(NULL, pub, (CFIndex)w * h * 4);
  CGDataProviderRef dp = CGDataProviderCreateWithCFData(data);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGImageRef im = CGImageCreate(w, h, 8, 32, (size_t)w * 4, cs, (CGBitmapInfo)kCGBitmapByteOrderDefault | (CGBitmapInfo)kCGImageAlphaLast,
                                dp, NULL, true, kCGRenderingIntentDefault);
  CGColorSpaceRelease(cs);
  CGDataProviderRelease(dp);
  CFRelease(data);
  return im;
}

// The wheel's parts, made once, hidden until it opens: a dim over the game,
// the dark disc, the slices on it, each slice's icon (twice for the two
// colts), its count and its name (shown instead of an icon the game couldn't
// give), the needle, the middle's lines and "cancel" in the gap
- (void)makeWheel
{
  wheelView = [[UIView alloc] initWithFrame:self.bounds];
  wheelView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  wheelView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
  wheelView.userInteractionEnabled = NO; // touches are the overlay's
  wheelView.hidden = YES;
  wheelDisc = [CAShapeLayer layer];
  wheelDisc.fillColor = [UIColor colorWithWhite:0.0 alpha:0.85].CGColor;
  [wheelView.layer addSublayer:wheelDisc];
  for (int i = 0; i < IOSTOUCH_WHEEL_MAX; i++) {
    CAShapeLayer *sl = [CAShapeLayer layer];
    sl.lineJoin = kCALineJoinRound;
    sl.hidden = YES;
    aSliceLayers[i] = sl;
    [wheelView.layer addSublayer:sl];
  }
  for (int i = 0; i < IOSTOUCH_WHEEL_MAX; i++) {
    for (int k = 1; k >= 0; k--) { // [1] (the two colts' back one) under [0]
      CALayer *l = [CALayer layer];
      l.zPosition = 2.0;
      l.hidden = YES;
      l.contentsGravity = kCAGravityResize;
      l.magnificationFilter = kCAFilterLinear;
      l.minificationFilter = kCAFilterLinear;
      aIconLayers[i][k] = l;
      [wheelView.layer addSublayer:l];
    }
    UILabel *c = [[UILabel alloc] initWithFrame:CGRectZero];
    c.textAlignment = NSTextAlignmentCenter;
    c.layer.zPosition = 2.0;
    c.hidden = YES;
    aCountLabels[i] = c;
    [wheelView addSubview:c];
    UILabel *n = [[UILabel alloc] initWithFrame:CGRectZero];
    n.textAlignment = NSTextAlignmentCenter;
    n.numberOfLines = 2;
    n.adjustsFontSizeToFitWidth = YES;
    n.minimumScaleFactor = 0.5;
    n.layer.zPosition = 2.0;
    n.hidden = YES;
    aNameLabels[i] = n;
    [wheelView addSubview:n];
  }
  wheelNeedle = [CAShapeLayer layer];
  wheelNeedle.lineWidth = 3.0;
  wheelNeedle.lineCap = kCALineCapRound;
  wheelNeedle.fillColor = [UIColor clearColor].CGColor;
  wheelNeedle.zPosition = 2.0;
  wheelNeedle.hidden = YES;
  [wheelView.layer addSublayer:wheelNeedle];
  for (int i = 0; i < IOSTOUCH_MIDDLE_LINES; i++) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.textAlignment = NSTextAlignmentCenter;
    l.layer.zPosition = 2.0;
    l.hidden = YES;
    aMiddleLabels[i] = l;
    [wheelView addSubview:l];
  }
  wheelCancelLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 80, 14)];
  wheelCancelLabel.textAlignment = NSTextAlignmentCenter;
  wheelCancelLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
  wheelCancelLabel.textColor = [UIColor colorWithWhite:0.59 alpha:1.0];
  wheelCancelLabel.text = @"cancel";
  wheelCancelLabel.layer.zPosition = 2.0;
  [wheelView addSubview:wheelCancelLabel];
  [self addSubview:wheelView];
  wheelTick = [[UISelectionFeedbackGenerator alloc] init];
  memset(&wheelKey, 0, sizeof(wheelKey));
}

// The icons the game has handed over since, as images: as they are, and
// greyed for no ammo and for not found yet
- (void)makeIconImages
{
  const unsigned int ulNew = _ulIconsNew;
  _ulIconsNew = 0;
  for (int w = 0; w < IOSTOUCH_WPN_MAX; w++) {
    if (!(ulNew & (1u << w))) continue;
    const IOSTouchIcon *pi = &_aIcons[w];
    for (int st = 0; st < WICON_NUM; st++) {
      aIconImages[w][st] = pi->bHave ? CFBridgingRelease(IOSTouch_MakeIconImage(pi->aub[st], pi->w, pi->h)) : nil;
    }
  }
  if (ulNew) bWheelRebuild = 1;
}

// Draws the open wheel as the core says: made again only when something
// changed (what is pointed at, the slices' states, an icon, the layout); the
// needle follows the thumb every time
- (void)refreshWheel
{
  IOSTouchWheelKey key;
  memset(&key, 0, sizeof(key));
  key.iMap = _iWheelMap;
  key.cx = _fWheelCX;
  key.cy = _fWheelCY;
  key.R1 = _fWheelR1;
  key.iHot = IOSTouch_WheelPointed(&key.bCancel, NULL);
  key.bTapMode = _bWheelTapMode;
  key.iWanted = _wpn.iWanted;
  key.ulOwned = _wpn.ulOwned;
  key.ulReady = _wpn.ulReady;
  key.bInfinite = _wpn.bInfiniteAmmo;
  memcpy(key.aiAmmo, _wpn.aiAmmo, sizeof(key.aiAmmo));
  memcpy(key.aiMax, _wpn.aiMaxAmmo, sizeof(key.aiMax));
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  const CGPoint c = CGPointMake(_fWheelCX, _fWheelCY);
  const double R0 = _fWheelR0, R1 = _fWheelR1;

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (bWheelRebuild || memcmp(&key, &wheelKey, sizeof(key)) != 0) {
    bWheelRebuild = 0;
    wheelKey = key;
    wheelView.frame = self.bounds;
    wheelDisc.path = [UIBezierPath bezierPathWithArcCenter:c radius:R1 + 14.0 startAngle:0.0 endAngle:2.0 * M_PI clockwise:YES].CGPath;
    const IOSTouchWheelFit *f = IOSTouch_WheelFit();
    for (int i = 0; i < IOSTOUCH_WHEEL_MAX; i++) {
      const int bOn = i < m->ctSlots;
      aSliceLayers[i].hidden = !bOn;
      aCountLabels[i].hidden = aNameLabels[i].hidden = YES;
      aIconLayers[i][0].hidden = aIconLayers[i][1].hidden = YES;
      if (!bOn) continue;
      IOSTouchWheelLook look;
      IOSTouch_WheelSlotLook(i, key.iHot, &look);
      const double deg = IOSTouch_WheelSlotDeg(m, i), half = m->fSliceDeg * 0.5 - 1.0; // a degree in from each edge
      CAShapeLayer *L = aSliceLayers[i];
      L.path = IOSTouch_WedgePath(c, deg - half, deg + half, R0, R1 + (look.bPopped ? IOSTOUCH_WHEEL_POP : 0.0)).CGPath;
      L.fillColor = IOSTouch_Colour(look.afFill).CGColor;
      L.strokeColor = IOSTouch_Colour(look.afEdge).CGColor;
      L.lineWidth = look.fLine;
      L.zPosition = look.bPopped ? 1.0 : 0.0;
      IOSTouchRect rIcon, rRow;
      IOSTouch_WheelSlotRects(i, look.bPopped, look.iCount >= 0, &rIcon, &rRow);
      const CGRect ri = CGRectMake(rIcon.x0, rIcon.y0, rIcon.x1 - rIcon.x0, rIcon.y1 - rIcon.y0);
      const int w = m->aSlots[i].iWeapon;
      id image = aIconImages[IOSTouch_WheelIconOf(w)][look.iIcon];
      if (image) {
        if (w == 3) {
          // the two colts: the colt's icon twice, the back one up and left
          const CGFloat s = ri.size.width * 0.82, d = ri.size.width - s;
          aIconLayers[i][1].frame = CGRectMake(ri.origin.x, ri.origin.y, s, s);
          aIconLayers[i][1].contents = image;
          aIconLayers[i][1].opacity = 0.85;
          aIconLayers[i][1].hidden = NO;
          aIconLayers[i][0].frame = CGRectMake(ri.origin.x + d, ri.origin.y + d, s, s);
        }
        else {
          aIconLayers[i][0].frame = ri;
        }
        aIconLayers[i][0].contents = image;
        aIconLayers[i][0].hidden = NO;
      }
      else {
        // no icon (yet): the name
        UILabel *n = aNameLabels[i];
        n.text = [[NSString stringWithUTF8String:m->aSlots[i].strName] stringByReplacingOccurrencesOfString:@" " withString:@"\n"];
        n.font = [UIFont systemFontOfSize:9.0 * f->k weight:UIFontWeightSemibold];
        n.textColor = IOSTouch_Colour(look.afText);
        n.bounds = CGRectMake(0, 0, ri.size.width, ri.size.height); // (the fitted block's width: it shrinks to fit)
        n.center = CGPointMake(CGRectGetMidX(ri), CGRectGetMidY(ri));
        n.hidden = NO;
      }
      if (look.iCount >= 0) {
        UILabel *cl = aCountLabels[i];
        cl.text = [NSString stringWithFormat:@"%d", look.iCount];
        cl.font = [UIFont monospacedDigitSystemFontOfSize:IOSTOUCH_WHEEL_AMMO_FONT * f->k weight:UIFontWeightSemibold];
        cl.textColor = IOSTouch_Colour(look.afText);
        cl.bounds = CGRectMake(0, 0, rRow.x1 - rRow.x0 + 6.0, ceil(IOSTOUCH_WHEEL_AMMO_FONT * f->k * 1.25)); // (a whole line)
        cl.center = CGPointMake((rRow.x0 + rRow.x1) * 0.5, (rRow.y0 + rRow.y1) * 0.5); // (the digits about centred in it)
        cl.hidden = NO;
      }
    }
    // the middle
    IOSTouchWheelMiddle mid;
    IOSTouch_WheelMiddleState(&mid);
    IOSTouchMiddleLine aLines[IOSTOUCH_MIDDLE_LINES];
    const int ct = IOSTouch_WheelMiddleLayout(R0, &mid, IOSTouch_MiddleTextWidth, NULL, aLines);
    for (int j = 0; j < IOSTOUCH_MIDDLE_LINES; j++) {
      UILabel *l = aMiddleLabels[j];
      l.hidden = j >= ct;
      if (j >= ct) continue;
      const IOSTouchMiddleLine *ln = &aLines[j];
      l.text = [NSString stringWithUTF8String:ln->str];
      l.font = IOSTouch_MiddleFont(ln->iKind, ln->fSize);
      if (ln->iKind == WLINE_TITLE) {
        float af[4];
        if (mid.iTitleLook == WTITLE_SLOT) IOSTouch_WheelMix(mid.iColour, 1.0, af);
        else IOSTouch_Grey(mid.iTitleLook == WTITLE_WHITE ? 1.0 : 0.63, 1.0, af);
        l.textColor = IOSTouch_Colour(af);
      }
      else {
        l.textColor = [UIColor colorWithWhite:(ln->iKind == WLINE_COUNT ? 0.9 : 0.8) alpha:1.0];
      }
      l.bounds = CGRectMake(0, 0, 2.0 * R0, ceil(ln->fSize * 1.18) + 2.0);
      l.center = CGPointMake(c.x, c.y + ln->fDY);
    }
    wheelCancelLabel.center = CGPointMake(c.x, c.y + R1 - 22.0);
    wheelCancelLabel.hidden = key.iHot == IOSTOUCH_WHEEL_CANCEL;
  }
  double x0, y0, x1, y1;
  float af[4];
  if (IOSTouch_WheelNeedle(&x0, &y0, &x1, &y1, af)) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(x0, y0)];
    [p addLineToPoint:CGPointMake(x1, y1)];
    wheelNeedle.path = p.CGPath;
    wheelNeedle.strokeColor = IOSTouch_Colour(af).CGColor;
    wheelNeedle.hidden = NO;
  }
  else {
    wheelNeedle.hidden = YES;
  }
  [CATransaction commit];
}

// The opener's button (NEXT WPN or PREV WPN) lifted above the wheel's dim
// (b), or put back where it was made, just above the button before it
// (-1), so the stick, the FPS readout and the tray draw over it again
- (void)liftWheelButton:(int)b
{
  if (iWheelLifted > 0) [self insertSubview:aButtonViews[iWheelLifted - 1] aboveSubview:aButtonViews[iWheelLifted - 2]];
  iWheelLifted = 0;
  if (b >= 0) {
    [self insertSubview:aButtonViews[b] aboveSubview:wheelView];
    iWheelLifted = b + 1;
  }
}

// After every touch, frame and reset: the wheel shows while the core has it
// open (the opener's button lifted above the dim), and ticks as the thumb
// moves onto another slice
- (void)syncWheel
{
  if (_ulIconsNew) [self makeIconImages];
  if (_bWheelOpen && !bWheelShown) {
    bWheelShown = 1;
    bWheelRebuild = 1;
    [self bringSubviewToFront:wheelView];
    [self liftWheelButton:_iWheelButton];
    [wheelTick prepare];
    wheelView.hidden = NO;
    [self refreshButtonLooks];
    [self refreshStick];
  }
  else if (!_bWheelOpen && bWheelShown) {
    bWheelShown = 0;
    wheelView.hidden = YES;
    [self liftWheelButton:-1];
    [self refreshButtonLooks];
  }
  else if (bWheelShown && iWheelLifted != _iWheelButton + 1) {
    // (closed and opened again from the other button between two syncs)
    [self liftWheelButton:_iWheelButton];
    [self refreshButtonLooks];
  }
  if (bWheelShown) [self refreshWheel];
  if (_ctWheelTicks > 0) {
    if (bWheelShown) [wheelTick selectionChanged];
    _ctWheelTicks = 0;
  }
}

// ------------------------------------------------------------ touches

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  const double now = CACurrentMediaTime();
  const double W = self.bounds.size.width;
  for (UITouch *t in touches) {
    CGPoint p = [t locationInView:self];
    IOSTouch_TouchBegan((__bridge const void *)t, p.x, p.y, W, now, t.timestamp);
  }
  [self refreshAll];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  int bLooksChanged = 0;
  for (UITouch *t in touches) {
    // the places UIKit merged into this move (the last one is t's own)
    for (UITouch *c in [event coalescedTouchesForTouch:t]) {
      CGPoint q = [c locationInView:self];
      IOSTouch_TouchPassed((__bridge const void *)t, q.x, q.y);
    }
    CGPoint p = [t locationInView:self];
    if (IOSTouch_TouchMoved((__bridge const void *)t, p.x, p.y)) bLooksChanged = 1;
  }
  if (bLooksChanged) [self refreshButtonLooks];
  [self refreshStick];
  [self refreshMessages];
  [self syncWheel];
}

- (void)endTouches:(NSSet<UITouch *> *)touches cancelled:(int)bCancelled
{
  for (UITouch *t in touches) {
    CGPoint p = [t locationInView:self];
    IOSTouch_TouchEnded((__bridge const void *)t, p.x, p.y, bCancelled, t.timestamp);
  }
  [self refreshAll];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self endTouches:touches cancelled:0]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self endTouches:touches cancelled:1]; }

// Once per frame while shown: the NEXT WPN, PREV WPN, QUICK SAVE, QUICK
// LOAD, MENU and unread messages holds, the weapon wheel, the context
// buttons and the FPS readout
- (void)tick
{
  const double now = CACurrentMediaTime();
  const int bTrayWasOpen = _bTrayOpen;
  const int iFpsWas = _iFpsShown;
  IOSTouch_TickHolds(now);
  IOSTouch_CountFrames(_ulFramesDrawn, now);
  [self setRing:saveRing progress:_fSaveRing];
  [self setRing:loadRing progress:_fLoadRing];
  [self setRing:menuRing progress:_fMenuRing];
  [self setRing:aWheelRings[0] progress:_afWheelRing[0]];
  [self setRing:aWheelRings[1] progress:_afWheelRing[1]];
  [self refreshMessages];
  [self syncWheel]; // (a hold may have opened the weapon wheel, or the game closed it)

  // BOMB says how many there are (IOSTouch_BombLabel)
  const int ctBombs = _hud.bValid ? _hud.ctBombs : 0;
  if (ctBombs != ctBombsShown) {
    ctBombsShown = ctBombs;
    char str[24];
    IOSTouch_BombLabel(ctBombs, str, sizeof(str));
    UILabel *l = aButtonViews[BTN_BOMB];
    l.text = [NSString stringWithUTF8String:str];
    l.font = [UIFont boldSystemFontOfSize:IOSTouch_FontSize(str, _aButtons[BTN_BOMB].radius)];
  }
  // ZOOM and BOMB come and go, the tray opens, the readout counts
  if (aButtonViews[BTN_ZOOM].hidden == IOSTouch_IsShown(BTN_ZOOM) || aButtonViews[BTN_BOMB].hidden == IOSTouch_IsShown(BTN_BOMB)
      || _bTrayOpen != bTrayWasOpen || _iFpsShown != iFpsWas) {
    [self refreshButtonLooks];
  }
}

- (void)resetAll
{
  IOSTouch_ResetTouches(_iMode == IOSTOUCH_GAMEPLAY && !self.hidden && self.superview != nil);
  [self refreshAll];
}

@end

// ---------------------------------------------------------------- C API

static IOSTouchOverlay *_pOverlay = nil;

// The view SDL draws the game in: the overlay goes on top of it
static UIView *IOSTouch_GetHostView(SDL_Window *pWindow)
{
  SDL_SysWMinfo info;
  SDL_VERSION(&info.version);
  if (pWindow == NULL || !SDL_GetWindowWMInfo(pWindow, &info) || info.subsystem != SDL_SYSWM_UIKIT) return nil;
  UIWindow *w = info.info.uikit.window;
  if (!w) return nil;
  return w.rootViewController.view ? w.rootViewController.view : w;
}

// Switches what shows; every change starts clean (touches on a hidden view
// never end, and MENU's tray closes)
static void IOSTouch_SetMode(int iMode)
{
  const int iOld = _iMode;
  _iMode = iMode;
  if (_pOverlay) {
    _pOverlay.hidden = (iMode == IOSTOUCH_HIDDEN);
    [_pOverlay resetAll];
  }
  else {
    IOSTouch_ResetTouches(0);
  }
  // The console gets the iOS keyboard. Hiding it also stops SDL's text
  // events, which the console and menus type with (e.g. on a hardware
  // keyboard): turn those back on.
  if (iMode == IOSTOUCH_CONSOLE && iOld != IOSTOUCH_CONSOLE) {
    SDL_StartTextInput();
  }
  else if (iOld == IOSTOUCH_CONSOLE && iMode != IOSTOUCH_CONSOLE) {
    SDL_StopTextInput();
    SDL_EventState(SDL_TEXTINPUT, SDL_ENABLE);
  }
}

// The console's iOS keyboard, while the console is open. iOS hides it when
// the app goes to the background (and an iPad's keyboard has a hide key);
// SDL takes that as the end of text input, so nothing brings it back by
// itself. Asked again at most twice a second, and only while the app is in
// front.
static void IOSTouch_KeepConsoleKeyboard(SDL_Window *pWindow)
{
  static double tAsked = 0.0;
  if (_iMode != IOSTOUCH_CONSOLE || SDL_IsScreenKeyboardShown(pWindow)) return;
  if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
  const double now = CACurrentMediaTime();
  if (now - tAsked < 0.5) return;
  tAsked = now;
  SDL_StartTextInput();
}

static int IOSTouch_UpdateOverlay(void *pSDLWindow, int iMode, const IOSTouchHud *pHud, unsigned int ulFramesDrawn)
{
  // what was asked for since the last frame (the main loop checks it still fits)
  const int iRequests = _iRequests;
  _iRequests = 0;
  _ulFramesDrawn = ulFramesDrawn;

  // the player may have closed the keyboard themselves, which stops text events too
  if (SDL_EventState(SDL_TEXTINPUT, SDL_QUERY) == SDL_DISABLE) {
    SDL_EventState(SDL_TEXTINPUT, SDL_ENABLE);
  }

  if (pHud) {
    _hud = *pHud;
    IOSTouch_KeepRect(&_rScoreFrac, pHud->afScore);
    IOSTouch_KeepRect(&_rHiScoreFrac, pHud->afHiScore);
    IOSTouch_KeepRect(&_rMessagesFrac, pHud->afMessages);
  }

  UIView *host = IOSTouch_GetHostView((SDL_Window *)pSDLWindow);
  // the HUD's frame, from the game's view: also while the overlay hides (the
  // HUD shows in demos too) and before it exists
  if (host) {
    const UIEdgeInsets in = host.safeAreaInsets;
    IOSTouch_SetHudFrame(host.bounds.size.width, host.bounds.size.height, in.left, in.top, in.right, in.bottom);
  }
  if (!_pOverlay) {
    if (iMode == IOSTOUCH_HIDDEN || !host) {
      _iMode = IOSTOUCH_HIDDEN;
      return iRequests;
    }
    _pOverlay = [[IOSTouchOverlay alloc] initWithFrame:host.bounds];
    _pOverlay.hidden = YES;
    [host addSubview:_pOverlay];
  }
  else if (host && _pOverlay.superview != host) {
    // SDL's window was recreated (a display mode change): the overlay is
    // still sitting in the old, no longer shown one -- move it across
    [_pOverlay removeFromSuperview];
    _pOverlay.frame = host.bounds;
    [host addSubview:_pOverlay];
    IOSTouch_SetMode(_iMode);
  }

  // keep it on top of anything SDL adds later (its text field, for the keyboard)
  if (_pOverlay.superview && _pOverlay.superview.subviews.lastObject != _pOverlay) {
    [_pOverlay.superview bringSubviewToFront:_pOverlay];
  }

  if (iMode != _iMode) {
    IOSTouch_SetMode(iMode);
  }
  IOSTouch_KeepConsoleKeyboard((SDL_Window *)pSDLWindow);

  if (iMode != IOSTOUCH_HIDDEN) {
    // The HUD is laid out again on resize and HUD scale changes. Turning the
    // phone the other way up changes neither the size nor the insets, but
    // moves the cutout to the other side.
    CGSize sz = _pOverlay.bounds.size;
    IOSTouchRect rScore = IOSTouch_RectInPoints(&_rScoreFrac, sz.width, sz.height);
    IOSTouchRect rHiScore = IOSTouch_RectInPoints(&_rHiScoreFrac, sz.width, sz.height);
    IOSTouchRect rMessages = IOSTouch_RectInPoints(&_rMessagesFrac, sz.width, sz.height);
    // where the HUD drew the messages box last (it drops down as a message comes in): not laid out for
    IOSTouchRect rNowFrac = { 0, 0, 0, 0, 0 };
    if (pHud) IOSTouch_KeepRect(&rNowFrac, pHud->afMessagesNow);
    _rMessagesNow = IOSTouch_RectInPoints(&rNowFrac, sz.width, sz.height);
    if (!IOSTouch_SameRect(&rScore, &_rLayoutScore) || !IOSTouch_SameRect(&rHiScore, &_rLayoutHiScore)
        || !IOSTouch_SameRect(&rMessages, &_rLayoutMessages)
        || IOSTouch_CutoutMayBeRight(_pOverlay) != _iLayoutCutoutRight) {
      [_pOverlay setNeedsLayout];
    }
    [_pOverlay tick];
  }

  // Tilt aiming, after the frame's touches came in: only while the overlay
  // is up and the app in front (the samples' side from the screen's)
  const int bHadGyro = IOSTouch_GyroAvailable();
  IOSTouch_GyroFrame(!_pOverlay.hidden && _pOverlay.superview != nil,
                     [UIApplication sharedApplication].applicationState == UIApplicationStateActive,
                     IOSTouch_ScreenSide(_pOverlay), CACurrentMediaTime());
  if (IOSTouch_GyroAvailable() != bHadGyro) {
    [_pOverlay refreshButtonLooks]; // iOS refused the motion data: the tray's GYRO says NO GYRO
  }
  return iRequests;
}

// These two run in the game's own loop, which SDL_main never leaves and
// where no autorelease pool is drained (SDL's event pumping drains only its
// own): each drains what it makes, or it would pile up while the game runs.
int IOSTouch_Update(void *pSDLWindow, int iMode, const IOSTouchHud *pHud, unsigned int ulFramesDrawn)
{
  int iRequests;
  @autoreleasepool {
    iRequests = IOSTouch_UpdateOverlay(pSDLWindow, iMode, pHud, ulFramesDrawn);
  }
  return iRequests;
}

void IOSTouch_Hide(void)
{
  @autoreleasepool {
    if (_iMode != IOSTOUCH_HIDDEN) IOSTouch_SetMode(IOSTOUCH_HIDDEN);
    IOSTouch_GyroRun(0); // no motion updates while loading or in the background
  }
}

// Called once per game tick. Held buttons report down for as long as they're
// held; a queued quick tap is reported down for IOSTOUCH_PULSE_READS ticks
// and then up for one, so the game sees each one as its own press. The
// weapon wheel's pick goes in the select field the same way, for
// IOSTOUCH_PULSE_READS ticks and then 0 for one (two picks in a row would
// otherwise run together: the game takes only the field's new bits); and
// never in a tick NEXT or PREV is read in, nor the tick after it (the game
// does the field first, then NEXT/PREV on top), whichever came first: a NEXT
// or PREV tap still waiting goes after a pick waiting or being read (it can
// only have come after the pick: opening the wheel drops the taps waiting),
// and a pick waits for a tap already being read and its gap.
void IOSTouch_ReadInput(IOSTouchInput *pInput)
{
  memset(pInput, 0, sizeof(*pInput));
  os_unfair_lock_lock(&_lock);
  if (_bReading) {
    pInput->fMoveX = _fMoveX;
    pInput->fMoveY = _fMoveY;
    const unsigned int ulWeaponKeys = IOSTOUCH_NEXTWEAPON | IOSTOUCH_PREVWEAPON;
    const int bPickBusy = _iPickPending || _iPickReads > 0 || _bPickGap; // (a NEXT/PREV tap waits)
    int bKeysBusy = 0;                                  // NEXT/PREV read now, or this is the tick after
    for (int i = 0; i < IOSTOUCH_NUMBUTTONS; i++) {
      const unsigned int ul = 1u << i;
      const int bHeld = (_ulHeld & ul) != 0;
      int bDown = bHeld;
      if (bHeld) _ulSeen |= ul;
      if ((ul & ulWeaponKeys) && (_aPulseReads[i] || _aPulseGap[i])) bKeysBusy = 1;
      if (_aPulseReads[i]) {
        if (--_aPulseReads[i] == 0) _aPulseGap[i] = 1;
        bDown = 1;
      }
      else if (_aPulseGap[i]) {
        _aPulseGap[i] = 0;
      }
      else if (_aPulseQueue[i] && !((ul & ulWeaponKeys) && bPickBusy)) {
        _aPulseQueue[i]--;
        _aPulseReads[i] = IOSTOUCH_PULSE_READS - 1;
        if (!_aPulseReads[i]) _aPulseGap[i] = 1;
        bDown = 1;
      }
      if ((ul & ulWeaponKeys) && (bDown || _aPulseReads[i] || _aPulseGap[i])) bKeysBusy = 1;
      if (bDown) pInput->ulButtons |= ul;
    }
    if (_iPickReads > 0) {
      if (--_iPickReads == 0) _bPickGap = 1;
      pInput->iSelectWeapon = _iPickNow;
    }
    else if (_bPickGap) {
      _bPickGap = 0;
    }
    else if (_iPickPending && !bKeysBusy) {
      _iPickNow = _iPickPending;
      _iPickPending = 0;
      _iPickReads = IOSTOUCH_PULSE_READS - 1;
      if (!_iPickReads) _bPickGap = 1;
      pInput->iSelectWeapon = _iPickNow;
    }
  }
  os_unfair_lock_unlock(&_lock);
}

void IOSTouch_TakeLook(float *pfDX, float *pfDY)
{
  os_unfair_lock_lock(&_lock);
  *pfDX = _bReading ? _fLookX : 0.0f;
  *pfDY = _bReading ? _fLookY : 0.0f;
  _fLookX = _fLookY = 0.0f;
  os_unfair_lock_unlock(&_lock);
}

void IOSTouch_TakeGyro(float *pfYaw, float *pfPitch)
{
  os_unfair_lock_lock(&_lock);
  *pfYaw = _bReading ? _fGyroYaw : 0.0f;
  *pfPitch = _bReading ? _fGyroPitch : 0.0f;
  _fGyroYaw = _fGyroPitch = 0.0f;
  os_unfair_lock_unlock(&_lock);
}
