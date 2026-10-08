/* On-screen touch controls for iOS. See IOSTouch.h.
   Built with ARC. The overlay lives for the whole process.

   Everything up to the overlay view is plain C: the buttons and their
   layout, the state shared with the game's thread, and what each touch does
   (the stick, looking, the buttons, the QUICK LOAD and MENU holds, MENU's
   tray, the FPS count). The view below only hands UIKit's touches to it and
   shows its state, so the Linux test drives this very code. */

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <os/lock.h>
#include <math.h>
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
// QUICK LOAD has to be held this long, so a stray tap can't throw away progress
#define IOSTOUCH_QUICKLOAD_HOLD 1.0
// MENU held this long opens its tray (the keyboard, FPS); a tap opens the
// menu as it lifts
#define IOSTOUCH_MENU_HOLD 0.45
// The FPS readout: its size in points, and how long it counts frames for
// before it shows a new number
#define IOSTOUCH_FPS_W 54.0
#define IOSTOUCH_FPS_H 18.0
#define IOSTOUCH_FPS_PERIOD 0.5
// A tap too quick for any game tick to see is reported for this many ticks,
// then released for one
#define IOSTOUCH_PULSE_READS 2

#define IOSTOUCH_MAX_TOUCHES 10

// ---------------------------------------------------------------- buttons

enum {
  KIND_HOLD = 0, // holds its game button while touched
  KIND_PRESS,    // presses its game button once when the touch lifts on it (BOMB: a look swipe can't waste one)
  KIND_MENU,     // asks for the menu when the touch lifts on it; held IOSTOUCH_MENU_HOLD, opens its tray
  KIND_TAP,      // asks for its request when the touch lifts on it
  KIND_HOLDLOAD, // asks for a quick load once held IOSTOUCH_QUICKLOAD_HOLD seconds
  KIND_KEYBOARD, // (MENU's tray) opens or closes the console, when the touch lifts on it
  KIND_FPS,      // (MENU's tray) shows or hides the FPS readout, when the touch lifts on it
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
// FIRE, an arc of CROUCH / USE / JUMP around it, ZOOM above the ammo row and
// BOMB right of JUMP -- all IOSTOUCH_CLUSTER_GAP apart; ZOOM and BOMB only
// show while they can be used. These pass drags through to looking, so a
// thumb that lands on one while aiming keeps aiming -- except BOMB, which
// goes off as the finger lifts on it (bombs are few: a look swipe that
// starts on it mustn't use one up). Top left, below the
// score: next and previous weapon. Top right: quick save, quick load (hold)
// and the menu. Holding MENU opens a tray just under it: the keyboard, for
// the console (cheats), and FPS, which shows or hides a frame rate readout
// left of QUICK SAVE. RESUME, in the middle, only while the game is paused.
enum {
  BTN_FIRE, BTN_ZOOM, BTN_CROUCH, BTN_USE, BTN_JUMP, BTN_BOMB,
  BTN_NEXTWPN, BTN_PREVWPN,
  BTN_QUICKSAVE, BTN_QUICKLOAD, BTN_MENU,
  BTN_RESUME,
  BTN_TRAYFPS, BTN_TRAYKEYS, // MENU's tray, hidden unless it is open
  BTN_COUNT
};
static IOSTouchButton _aButtons[] = {
  [BTN_FIRE]      = { "FIRE",        KIND_HOLD,     IOSTOUCH_FIRE,          42.0, 1, SHOW_PLAY },
  [BTN_ZOOM]      = { "ZOOM",        KIND_HOLD,     IOSTOUCH_ZOOM,          28.0, 1, SHOW_PLAY },
  [BTN_CROUCH]    = { "CROUCH",      KIND_HOLD,     IOSTOUCH_CROUCH,        29.0, 1, SHOW_PLAY },
  [BTN_USE]       = { "USE",         KIND_HOLD,     IOSTOUCH_USE,           29.0, 1, SHOW_PLAY },
  [BTN_JUMP]      = { "JUMP",        KIND_HOLD,     IOSTOUCH_JUMP,          31.0, 1, SHOW_PLAY },
  [BTN_BOMB]      = { "BOMB",        KIND_PRESS,    IOSTOUCH_BOMB,          30.0, 0, SHOW_PLAY },
  [BTN_NEXTWPN]   = { "NEXT\nWPN",   KIND_HOLD,     IOSTOUCH_NEXTWEAPON,    22.0, 0, SHOW_PLAY },
  [BTN_PREVWPN]   = { "PREV\nWPN",   KIND_HOLD,     IOSTOUCH_PREVWEAPON,    22.0, 0, SHOW_PLAY },
  [BTN_QUICKSAVE] = { "QUICK\nSAVE", KIND_TAP,      IOSTOUCH_REQ_QUICKSAVE, 22.0, 0, SHOW_PLAY },
  [BTN_QUICKLOAD] = { "QUICK\nLOAD", KIND_HOLDLOAD, IOSTOUCH_REQ_QUICKLOAD, 22.0, 0, SHOW_PLAY },
  [BTN_MENU]      = { "MENU",        KIND_MENU,     IOSTOUCH_REQ_MENU,      22.0, 0, SHOW_ALL },
  [BTN_RESUME]    = { "RESUME",      KIND_TAP,      IOSTOUCH_REQ_RESUME,    44.0, 0, SHOW_PAUSE },
  [BTN_TRAYFPS]   = { "FPS",         KIND_FPS,      0,                      20.0, 0, SHOW_ALL },
  [BTN_TRAYKEYS]  = { "",            KIND_KEYBOARD, IOSTOUCH_REQ_CONSOLE,   20.0, 0, SHOW_ALL },
};
#define IOSTOUCH_NUM_BUTTONS ((int)(sizeof(_aButtons) / sizeof(_aButtons[0])))
typedef char IOSTouch_assertButtonCount[(IOSTOUCH_NUM_BUTTONS == BTN_COUNT) ? 1 : -1];

// ------------------------------------------------------- shared with the game
// The game reads these on its own thread (IOSTouch_ReadInput, 20 times a
// second; IOSTouch_TakeLook, also every frame): only touch them under _lock.

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
  os_unfair_lock_unlock(&_lock);
}

// ---------------------------------------------------------------- layout

typedef struct {
  int bValid;
  double x0, y0, x1, y1;
} IOSTouchRect;

// What the layout puts besides the buttons (points): the backing behind
// MENU's tray, and the FPS readout's centre
static IOSTouchRect _rTrayBack;
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

// Places every button on a W x H point screen with these safe-area insets,
// keeping clear of the HUD's score and high score boxes, ammo row and unread
// messages box (in points) and of the camera cutout when it may be on the
// right. FIRE itself may cover the messages box's envelope icon; the count
// stays clear.
static void IOSTouch_LayoutButtons(double W, double H, double inLeft, double inTop, double inRight, double inBottom,
                                   int bCutoutMayBeRight, const IOSTouchRect *prScore, const IOSTouchRect *prHiScore,
                                   const IOSTouchRect *prAmmo, const IOSTouchRect *prMessages)
{
  const double left = fmax(inLeft, 8.0);
  const double right = W - fmax(inRight, 8.0);
  const double top = fmax(inTop, 8.0);
  const double bottom = H - fmax(inBottom, 8.0);

  // FIRE in the corner. On screens without a bottom inset (Home-button
  // iPhones, iPads) the ammo row reaches up to there: FIRE goes above it.
  // Without side insets there is no spare edge for ZOOM to sit in beside
  // FIRE, so FIRE sits further in.
  const double FR = _aButtons[BTN_FIRE].radius;
  double fireX = right - (inRight < 20.0 ? 100 : 76), fireY = bottom - 58;
  if (prAmmo->bValid && fireY + FR + 4 > prAmmo->y0) {
    fireY = prAmmo->y0 - 4 - FR;
  }
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
  // it can sit while staying clear of the ammo row and the messages box, on
  // screen, clear of JUMP and clear of the cutout.
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
        for (int deg = 10; deg <= 85; deg++) {
          const double rad = deg * M_PI / 180.0;
          const double px = fireX + (D + extra) * cos(rad), py = fireY - (D + extra) * sin(rad);
          if (px + AR > W - 4 || py - AR < top + 60) continue;                           // on screen, below the top row
          if (prAmmo->bValid && IOSTouch_DistToRect(px, py, prAmmo) < AR + 4) continue;   // clear of the ammo row
          if (prMessages->bValid && IOSTouch_DistToRect(px, py, prMessages) < AR + 4) continue; // and the messages
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
    // Last resort (e.g. a very large HUD on an iPad): never on the ammo row
    if (!bFound && prAmmo->bValid && by + AR > prAmmo->y0 - 4) {
      by = fmax(prAmmo->y0 - 4 - AR, top + 60 + AR);
    }
    a->x = bx;
    a->y = by;
  }

  // BOMB: right of JUMP and above ZOOM, out of the way of aiming -- on the
  // circle IOSTOUCH_CLUSTER_GAP out from JUMP, as far round towards pointing
  // right as it fits on screen, below the top row and clear of ZOOM, USE,
  // FIRE, the ammo row, the messages box and the cutout. Where the cutout (or, on smaller
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
        if (prAmmo->bValid && IOSTouch_DistToRect(px, py, prAmmo) < R + 4) continue; // the ammo row
        if (prMessages->bValid && IOSTouch_DistToRect(px, py, prMessages) < R + 4) continue; // the messages
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
  // apart, so a press meant for QUICK LOAD can't land on QUICK SAVE
  _aButtons[BTN_QUICKSAVE].x = right - 156;
  _aButtons[BTN_QUICKLOAD].x = right - 90;
  _aButtons[BTN_MENU].x = right - 24;
  _aButtons[BTN_QUICKSAVE].y = _aButtons[BTN_QUICKLOAD].y = _aButtons[BTN_MENU].y = top + 26;

  // MENU's tray: a row just under the corner, the keyboard right below MENU
  // (a held thumb slides straight down onto it) and FPS left of that. Where
  // BOMB, ZOOM or JUMP sits high in that corner (a smaller screen) the row
  // moves left until it is clear of them -- or, if that never happens, to
  // wherever it is furthest from them. (While open, the tray is on top and
  // takes its own touches, but a touch meant for it mustn't land nearer one
  // of those.)
  {
    const IOSTouchButton *m = &_aButtons[BTN_MENU];
    const int aAvoid[3] = { BTN_BOMB, BTN_ZOOM, BTN_JUMP };
    const double ty = m->y + 52;
    double kx = m->x, bestGap = -1e9;
    for (double x = m->x; x >= m->x - 160; x -= 4) {
      double gap = 1e9;
      for (int i = 0; i < 3; i++) {
        const IOSTouchButton *f = &_aButtons[aAvoid[i]];
        gap = fmin(gap, IOSTouch_DistToSegment(f->x, f->y, x - 50, ty, x, ty) - 26 - f->radius);
      }
      if (gap > bestGap) {
        bestGap = gap;
        kx = x;
      }
      if (gap >= 8) break;
    }
    _aButtons[BTN_TRAYKEYS].x = kx;
    _aButtons[BTN_TRAYKEYS].y = ty;
    _aButtons[BTN_TRAYFPS].x = kx - 50;
    _aButtons[BTN_TRAYFPS].y = ty;
    _rTrayBack.bValid = 1;
    _rTrayBack.x0 = kx - 50 - 26;
    _rTrayBack.y0 = ty - 26;
    _rTrayBack.x1 = kx + 26;
    _rTrayBack.y1 = ty + 26;
  }

  // The FPS readout where the keyboard button used to be, left of QUICK SAVE:
  // the game prints its messages at the top left, and its high score box is
  // in the middle. On a narrow screen, where that spot is on the high score
  // box, it moves right towards QUICK SAVE; if it never fits there, it goes
  // below QUICK SAVE (and on to the left), clear of BOMB and ZOOM as well.
  {
    const IOSTouchButton *q = &_aButtons[BTN_QUICKSAVE];
    const IOSTouchRect *const apr[4] = { prScore, prHiScore, prAmmo, prMessages };
    const int aAvoid[2] = { BTN_BOMB, BTN_ZOOM };
    const double hw = IOSTOUCH_FPS_W * 0.5, hh = IOSTOUCH_FPS_H * 0.5;
    const double y2 = q->y + q->radius + 8 + hh;
    int bFound = 0;
    _fFpsX = right - 216;
    _fFpsY = top + 26;
    for (double x = right - 216; x <= q->x - q->radius - 6 - hw && !bFound; x += 2) {
      if (IOSTouch_BoxIsClear(x, top + 26, hw, hh, apr, 4, NULL, 0)) {
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
  // at 0.4 of the height)
  _aButtons[BTN_RESUME].x = (left + right) * 0.5;
  _aButtons[BTN_RESUME].y = fmax((top + bottom) * 0.5, H * 0.4 + 60.0);
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

// ---------------------------------------------------------------- touches
// Main thread. The overlay view hands each touch to IOSTouch_TouchBegan /
// Moved / Ended (points, seconds) and calls IOSTouch_TickHolds once a frame;
// it shows what the state below says.

typedef enum {
  ROLE_NONE = 0,
  ROLE_STICK,
  ROLE_LOOK,
  ROLE_BUTTON,
  ROLE_IGNORED, // not on a button while only buttons are live, or only closed MENU's tray; ignored until it lifts
} IOSTouchRole;

typedef struct {
  const void *touch;    // the UITouch: only compared, never used after it ends (NULL: a free slot)
  IOSTouchRole role;
  int button;
  double x, y;          // where it is now
  double tDown;         // when it began (QUICK LOAD: when it was last on the button)
  int bFired;           // QUICK LOAD: already asked for this touch. MENU: the hold is over (tray opened, or slid off)
  int trayButton;       // MENU, after its tray opened: the tray button under the finger, or -1
} IOSTouchSlot;

static IOSTouchSlot _aSlots[IOSTOUCH_MAX_TOUCHES];
static int _aButtonHeld[IOSTOUCH_NUM_BUTTONS]; // touches on each button
static int _bStickActive = 0;
static double _fStickOriginX = 0.0, _fStickOriginY = 0.0; // where the stick's thumb came down
static float _fStickX = 0.0f, _fStickY = 0.0f;           // -1..1 of the radius, screen axes
static int _iMode = IOSTOUCH_HIDDEN;
static int _iRequests = 0;                 // IOSTOUCH_REQ_* not handed out yet
static IOSTouchHud _hud;                   // the latest HUD state
static int _bTrayOpen = 0;                 // MENU's tray
static int _bShowFps = 0;                  // the FPS readout (the view keeps it in the app's settings)
static float _fLoadRing = 0.0f, _fMenuRing = 0.0f; // how far QUICK LOAD's and MENU's hold rings have filled
// The FPS readout: frames counted since _ulFpsFrames at _tFpsBase, and the
// number it shows (-1: none measured yet)
static int _bFpsBase = 0;
static unsigned int _ulFpsFrames = 0;
static double _tFpsBase = 0.0;
static int _iFpsShown = -1;

// Whether a button shows now
static int IOSTouch_IsShown(int button)
{
  if (!(_aButtons[button].iShowIn & (1 << _iMode))) return 0;
  if (button == BTN_ZOOM) return _hud.bValid && _hud.bSniper;
  if (button == BTN_BOMB) return _hud.bValid && _hud.ctBombs > 0;
  if (button == BTN_TRAYFPS || button == BTN_TRAYKEYS) return _bTrayOpen;
  return 1;
}

// Closest showing button the touch is on (with a little forgiveness), so a
// touch in the gap between two buttons picks the nearer one rather than the
// first listed.
static int IOSTouch_ButtonAt(double x, double y)
{
  int best = -1;
  double bestDist = 0;
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

static int IOSTouch_IsTrayButton(int button)
{
  return button == BTN_TRAYKEYS || button == BTN_TRAYFPS;
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

// A tray button picked: it does its thing, and the tray closes
static void IOSTouch_UseTrayButton(int button)
{
  if (_aButtons[button].kind == KIND_KEYBOARD) {
    _iRequests |= _aButtons[button].ulAction; // the console, with the iOS keyboard
  }
  else if (_aButtons[button].kind == KIND_FPS) {
    IOSTouch_SetShowFps(!_bShowFps);
  }
  IOSTouch_SetTrayOpen(0);
}

// A finger came down at (x,y) on a screen W points wide
static void IOSTouch_TouchBegan(const void *touch, double x, double y, double W, double now)
{
  IOSTouchSlot *s = IOSTouch_FindSlot(NULL);
  if (!s || !touch) return;
  memset(s, 0, sizeof(*s));
  s->touch = touch;
  s->x = x;
  s->y = y;
  s->tDown = now;
  s->trayButton = -1;
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

  if (s->button >= 0) {
    s->role = ROLE_BUTTON;
    _aButtonHeld[s->button]++;
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
// thumb held on MENU slid onto or off a tray button).
static int IOSTouch_TouchMoved(const void *touch, double x, double y, double now)
{
  IOSTouchSlot *s = touch ? IOSTouch_FindSlot(touch) : NULL;
  if (!s) return 0;
  int bLooksChanged = 0;
  if (s->role == ROLE_BUTTON && s->button == BTN_MENU && s->bFired && _bTrayOpen) {
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
  // QUICK LOAD only counts while the finger stays on it (IOSTouch_TickHolds
  // also checks every frame, for a finger that slid off and keeps still)
  if (s->role == ROLE_BUTTON && s->button == BTN_QUICKLOAD && !IOSTouch_IsOnButton(x, y, BTN_QUICKLOAD)) {
    s->tDown = now;
  }
  s->x = x;
  s->y = y;
  return bLooksChanged;
}

// A finger lifted at (x,y). bCancelled: iOS took the touch away (a call, a
// system gesture...) -- release whatever it held, but don't treat it as a
// finished tap.
static void IOSTouch_TouchEnded(const void *touch, double x, double y, int bCancelled)
{
  IOSTouchSlot *s = touch ? IOSTouch_FindSlot(touch) : NULL;
  if (!s) return;
  unsigned int ulLifted = 0;
  if (s->role == ROLE_BUTTON) {
    const IOSTouchButton *b = &_aButtons[s->button];
    if (_aButtonHeld[s->button] > 0) _aButtonHeld[s->button]--;
    // A tap so quick that no game tick saw it held still counts as one press
    if (!bCancelled && b->kind == KIND_HOLD && _aButtonHeld[s->button] == 0) {
      ulLifted |= b->ulAction;
    }
    // These act when the finger lifts on the button, so a slip onto one can
    // be dragged off again
    if (!bCancelled && IOSTouch_IsOnButton(x, y, s->button)) {
      if (b->kind == KIND_TAP) {
        _iRequests |= b->ulAction;
      }
      else if (b->kind == KIND_PRESS) {
        ulLifted |= b->ulAction; // never held, so the game gets it as one press
      }
      else if (b->kind == KIND_KEYBOARD || b->kind == KIND_FPS) {
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
    if (s->button == BTN_QUICKLOAD) _fLoadRing = 0.0f;
    if (s->button == BTN_MENU) _fMenuRing = 0.0f;
  }
  else if (s->role == ROLE_STICK) {
    _bStickActive = 0;
    _fStickX = _fStickY = 0.0f;
    IOSTouch_SetMoveFromStick();
  }
  memset(s, 0, sizeof(*s));
  IOSTouch_SetHeld(IOSTouch_HeldButtons(), ulLifted);
}

// Once per frame while shown: the QUICK LOAD and MENU holds
static void IOSTouch_TickHolds(double now)
{
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    IOSTouchSlot *s = &_aSlots[i];
    if (!s->touch || s->role != ROLE_BUTTON || s->bFired) continue;
    if (s->button == BTN_QUICKLOAD) {
      if (!IOSTouch_IsOnButton(s->x, s->y, BTN_QUICKLOAD)) {
        // off it: the hold starts over once the finger is back on it
        s->tDown = now;
        _fLoadRing = 0.0f;
        continue;
      }
      const double progress = (now - s->tDown) / IOSTOUCH_QUICKLOAD_HOLD;
      if (progress >= 1.0) {
        s->bFired = 1;
        _fLoadRing = 0.0f;
        _iRequests |= IOSTOUCH_REQ_QUICKLOAD;
      }
      else {
        _fLoadRing = (float)progress;
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

// Lets go of every touch and closes the tray (on every change of mode);
// bReading: whether the game gets input now
static void IOSTouch_ResetTouches(int bReading)
{
  IOSTouch_SetTrayOpen(0);
  memset(_aSlots, 0, sizeof(_aSlots));
  memset(_aButtonHeld, 0, sizeof(_aButtonHeld));
  _bStickActive = 0;
  _fStickX = _fStickY = 0.0f;
  _iRequests = 0;
  _fLoadRing = _fMenuRing = 0.0f;
  _bFpsBase = 0;
  IOSTouch_ResetShared(bReading);
}

// ---------------------------------------------------------------- overlay view

// Kept in the app's settings: whether the FPS readout shows
#define IOSTOUCH_FPS_DEFAULTS_KEY @"iosTouchShowFps"

static IOSTouchRect _rScoreFrac, _rHiScoreFrac, _rAmmoFrac, _rMessagesFrac; // the last boxes the HUD showed (fractions)
// What the current layout was made for
static IOSTouchRect _rLayoutScore, _rLayoutHiScore, _rLayoutAmmo, _rLayoutMessages; // in points
static int _iLayoutCutoutRight = -1;
static unsigned int _ulFramesDrawn = 0; // the game's frame count at the last IOSTouch_Update

// Whether the camera cutout may be on the right of the screen. Landscape right
// has the bottom of the phone on the right, so the cutout (at the top) is on
// the left; landscape left puts it on the right. SDL2 makes its window without
// a scene, so ask SDL (which follows the status bar) if there is none. Not
// known yet: assume it can be.
static int IOSTouch_CutoutMayBeRight(UIView *v)
{
  UIWindowScene *scene = v.window.windowScene;
  if (scene) return scene.interfaceOrientation != UIInterfaceOrientationLandscapeRight;
  return SDL_GetDisplayOrientation(0) != SDL_ORIENTATION_LANDSCAPE; // = landscape right
}

@interface IOSTouchOverlay : UIView {
  UIView *stickBase;
  UIView *stickKnob;
  UILabel *aButtonViews[IOSTOUCH_NUM_BUTTONS];
  CAShapeLayer *loadRing; // QUICK LOAD's hold progress
  CAShapeLayer *menuRing; // MENU's
  UIView *trayBack;       // behind MENU's tray
  UILabel *fpsLabel;      // the FPS readout...
  int iFpsLabel;          // ...the number it says (-1: none yet)
  int bFpsSaved;          // whether the app's settings say it shows
  int ctBombsShown;       // what BOMB's label says (-1: not yet set)
}
- (void)resetAll;
- (void)tick;
- (void)refreshButtonLooks;
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

    // Rings that fill while QUICK LOAD and MENU are held
    loadRing = IOSTouch_MakeHoldRing(_aButtons[BTN_QUICKLOAD].radius);
    [aButtonViews[BTN_QUICKLOAD].layer addSublayer:loadRing];
    menuRing = IOSTouch_MakeHoldRing(_aButtons[BTN_MENU].radius);
    [aButtonViews[BTN_MENU].layer addSublayer:menuRing];

    // MENU's tray: its two buttons on a dark backing, hidden until a hold on
    // MENU opens it. The keyboard button shows the keyboard symbol.
    trayBack = [[UIView alloc] initWithFrame:CGRectZero];
    trayBack.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    trayBack.layer.cornerRadius = 26.0;
    trayBack.layer.borderWidth = 1.5;
    trayBack.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    trayBack.userInteractionEnabled = NO;
    trayBack.hidden = YES;
    [self insertSubview:trayBack belowSubview:aButtonViews[BTN_TRAYFPS]];
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
  _rLayoutAmmo = IOSTouch_RectInPoints(&_rAmmoFrac, W, H);
  _rLayoutMessages = IOSTouch_RectInPoints(&_rMessagesFrac, W, H);
  _iLayoutCutoutRight = IOSTouch_CutoutMayBeRight(self);
  IOSTouch_LayoutButtons(W, H, in.left, in.top, in.right, in.bottom, _iLayoutCutoutRight,
                         &_rLayoutScore, &_rLayoutHiScore, &_rLayoutAmmo, &_rLayoutMessages);

  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    aButtonViews[i].center = CGPointMake(_aButtons[i].x, _aButtons[i].y);
  }
  trayBack.frame = CGRectMake(_rTrayBack.x0, _rTrayBack.y0, _rTrayBack.x1 - _rTrayBack.x0, _rTrayBack.y1 - _rTrayBack.y0);
  fpsLabel.center = CGPointMake(_fFpsX, _fFpsY);
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

// Which buttons show and how; the tray and the FPS readout
- (void)refreshButtonLooks
{
  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    UILabel *l = aButtonViews[i];
    const int bShown = IOSTouch_IsShown(i);
    if (l.hidden == bShown) l.hidden = !bShown;
    int bHeld = _aButtonHeld[i] != 0;
    // A thumb still on MENU after its tray opened lights the tray button it is over
    for (int t = 0; t < IOSTOUCH_MAX_TOUCHES && !bHeld; t++) {
      const IOSTouchSlot *s = &_aSlots[t];
      bHeld = s->touch && s->role == ROLE_BUTTON && s->button == BTN_MENU && s->bFired && s->trayButton == i;
    }
    l.backgroundColor = [UIColor colorWithWhite:(bHeld ? 1.0 : 0.0) alpha:(bHeld ? 0.30 : 0.22)];
    // The open console (on MENU and the tray's keyboard) and the FPS readout
    // being on (on the tray's FPS) stand out in yellow, at full strength
    const int bOn = ((i == BTN_TRAYKEYS || i == BTN_MENU) && _iMode == IOSTOUCH_CONSOLE)
                    || (i == BTN_TRAYFPS && _bShowFps);
    const int bTray = IOSTouch_IsTrayButton(i); // only there while the tray is open
    l.alpha = (bHeld || bOn || bTray) ? 1.0 : IOSTOUCH_IDLE_ALPHA;
    if (i != BTN_FIRE) {
      l.layer.borderColor = bOn ? [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:0.95].CGColor
                                : [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    }
  }
  if (trayBack.hidden == _bTrayOpen) trayBack.hidden = !_bTrayOpen;

  // The FPS readout, and the app's settings when it was switched on or off
  if (fpsLabel.hidden == _bShowFps) fpsLabel.hidden = !_bShowFps;
  if (bFpsSaved != _bShowFps) {
    bFpsSaved = _bShowFps;
    [[NSUserDefaults standardUserDefaults] setBool:(_bShowFps ? YES : NO) forKey:IOSTOUCH_FPS_DEFAULTS_KEY];
  }
  if (iFpsLabel != _iFpsShown) {
    iFpsLabel = _iFpsShown;
    fpsLabel.text = (_iFpsShown < 0) ? @"-- FPS" : [NSString stringWithFormat:@"%d FPS", _iFpsShown];
  }
}

- (void)refreshAll
{
  [self refreshButtonLooks];
  [self refreshStick];
  [self setRing:loadRing progress:_fLoadRing];
  [self setRing:menuRing progress:_fMenuRing];
}

// ------------------------------------------------------------ touches

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  const double now = CACurrentMediaTime();
  const double W = self.bounds.size.width;
  for (UITouch *t in touches) {
    CGPoint p = [t locationInView:self];
    IOSTouch_TouchBegan((__bridge const void *)t, p.x, p.y, W, now);
  }
  [self refreshAll];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  const double now = CACurrentMediaTime();
  int bLooksChanged = 0;
  for (UITouch *t in touches) {
    CGPoint p = [t locationInView:self];
    if (IOSTouch_TouchMoved((__bridge const void *)t, p.x, p.y, now)) bLooksChanged = 1;
  }
  if (bLooksChanged) [self refreshButtonLooks];
  [self refreshStick];
}

- (void)endTouches:(NSSet<UITouch *> *)touches cancelled:(int)bCancelled
{
  for (UITouch *t in touches) {
    CGPoint p = [t locationInView:self];
    IOSTouch_TouchEnded((__bridge const void *)t, p.x, p.y, bCancelled);
  }
  [self refreshAll];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self endTouches:touches cancelled:0]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self endTouches:touches cancelled:1]; }

// Once per frame while shown: the QUICK LOAD and MENU holds, the context
// buttons and the FPS readout
- (void)tick
{
  const double now = CACurrentMediaTime();
  const int bTrayWasOpen = _bTrayOpen;
  const int iFpsWas = _iFpsShown;
  IOSTouch_TickHolds(now);
  IOSTouch_CountFrames(_ulFramesDrawn, now);
  [self setRing:loadRing progress:_fLoadRing];
  [self setRing:menuRing progress:_fMenuRing];

  // BOMB says how many there are
  const int ctBombs = _hud.bValid ? _hud.ctBombs : 0;
  if (ctBombs != ctBombsShown) {
    ctBombsShown = ctBombs;
    UILabel *l = aButtonViews[BTN_BOMB];
    l.text = ctBombs > 1 ? [NSString stringWithFormat:@"BOMB\n%d", ctBombs] : @"BOMB";
    l.font = [UIFont boldSystemFontOfSize:(ctBombs > 1 ? 10 : 13)];
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
    IOSTouch_KeepRect(&_rAmmoFrac, pHud->afAmmo);
    IOSTouch_KeepRect(&_rMessagesFrac, pHud->afMessages);
  }

  UIView *host = IOSTouch_GetHostView((SDL_Window *)pSDLWindow);
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
    IOSTouchRect rAmmo = IOSTouch_RectInPoints(&_rAmmoFrac, sz.width, sz.height);
    IOSTouchRect rMessages = IOSTouch_RectInPoints(&_rMessagesFrac, sz.width, sz.height);
    if (!IOSTouch_SameRect(&rScore, &_rLayoutScore) || !IOSTouch_SameRect(&rHiScore, &_rLayoutHiScore)
        || !IOSTouch_SameRect(&rAmmo, &_rLayoutAmmo) || !IOSTouch_SameRect(&rMessages, &_rLayoutMessages)
        || IOSTouch_CutoutMayBeRight(_pOverlay) != _iLayoutCutoutRight) {
      [_pOverlay setNeedsLayout];
    }
    [_pOverlay tick];
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
  }
}

// Called once per game tick. Held buttons report down for as long as they're
// held; a queued quick tap is reported down for IOSTOUCH_PULSE_READS ticks
// and then up for one, so the game sees each one as its own press.
void IOSTouch_ReadInput(IOSTouchInput *pInput)
{
  memset(pInput, 0, sizeof(*pInput));
  os_unfair_lock_lock(&_lock);
  if (_bReading) {
    pInput->fMoveX = _fMoveX;
    pInput->fMoveY = _fMoveY;
    for (int i = 0; i < IOSTOUCH_NUMBUTTONS; i++) {
      const unsigned int ul = 1u << i;
      const int bHeld = (_ulHeld & ul) != 0;
      int bDown = bHeld;
      if (bHeld) _ulSeen |= ul;
      if (_aPulseReads[i]) {
        if (--_aPulseReads[i] == 0) _aPulseGap[i] = 1;
        bDown = 1;
      }
      else if (_aPulseGap[i]) {
        _aPulseGap[i] = 0;
      }
      else if (_aPulseQueue[i]) {
        _aPulseQueue[i]--;
        _aPulseReads[i] = IOSTOUCH_PULSE_READS - 1;
        if (!_aPulseReads[i]) _aPulseGap[i] = 1;
        bDown = 1;
      }
      if (bDown) pInput->ulButtons |= ul;
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
