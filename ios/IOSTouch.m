/* On-screen touch controls for iOS. See IOSTouch.h.
   Built with ARC. The overlay lives for the whole process. */

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
// Pushed past IOSTOUCH_STICK_DEADZONE of the radius it starts moving, at
// IOSTOUCH_STICK_FULL it moves at full speed (below about half speed the
// player walks, and won't step off ledges).
#define IOSTOUCH_STICK_ZONE 0.42f
#define IOSTOUCH_STICK_RADIUS 60.0f
#define IOSTOUCH_STICK_DEADZONE 0.15f
#define IOSTOUCH_STICK_FULL 0.70f
// Buttons show at this opacity while untouched, so they hide less of the game;
// a touched one shows at full strength
#define IOSTOUCH_IDLE_ALPHA 0.65
// Edge-to-edge gap between the buttons around FIRE (the arc, ZOOM and BOMB)
#define IOSTOUCH_CLUSTER_GAP 30.0
// QUICK LOAD has to be held this long, so a stray tap can't throw away progress
#define IOSTOUCH_QUICKLOAD_HOLD 1.0
// A tap too quick for any game tick to see is reported for this many ticks,
// then released for one
#define IOSTOUCH_PULSE_READS 2

#define IOSTOUCH_MAX_TOUCHES 10

// ---------------------------------------------------------------- buttons

enum {
  KIND_HOLD = 0, // holds its game button while touched
  KIND_MENU,     // asks for the menu as soon as it is touched
  KIND_TAP,      // asks for its request when the touch lifts on the button
  KIND_HOLDLOAD, // asks for a quick load once held IOSTOUCH_QUICKLOAD_HOLD seconds
};

// which modes a button shows in
#define SHOW_PLAY  (1 << IOSTOUCH_GAMEPLAY)
#define SHOW_CONS  (1 << IOSTOUCH_CONSOLE)
#define SHOW_PAUSE (1 << IOSTOUCH_PAUSED)

typedef struct {
  const char *label;
  int kind;
  unsigned int ulAction; // KIND_HOLD: IOSTOUCH_FIRE...; otherwise IOSTOUCH_REQ_*
  double radius;         // points
  int bLookWhileHeld;    // dragging on this button also turns the view
  int iShowIn;           // SHOW_*
  double x, y;           // centre, set in layout
} IOSTouchButton;

// Layout (see IOSTouch_LayoutButtons). Bottom right, under the right thumb:
// FIRE, an arc of CROUCH / USE / JUMP around it, ZOOM above the ammo row and
// BOMB right of JUMP -- all IOSTOUCH_CLUSTER_GAP apart; ZOOM and BOMB only
// show while they can be used. These all pass drags through to looking, so a
// thumb that lands on one while aiming keeps aiming. Top left, below the
// score: next and previous weapon. Top right: the keyboard (console), quick
// save, quick load (hold) and the menu. RESUME, in the middle, only while
// the game is paused.
enum {
  BTN_FIRE, BTN_ZOOM, BTN_CROUCH, BTN_USE, BTN_JUMP, BTN_BOMB,
  BTN_NEXTWPN, BTN_PREVWPN,
  BTN_KEYBOARD, BTN_QUICKSAVE, BTN_QUICKLOAD, BTN_MENU,
  BTN_RESUME,
  BTN_COUNT
};
static IOSTouchButton _aButtons[] = {
  [BTN_FIRE]      = { "FIRE",        KIND_HOLD,     IOSTOUCH_FIRE,          42.0, 1, SHOW_PLAY },
  [BTN_ZOOM]      = { "ZOOM",        KIND_HOLD,     IOSTOUCH_ZOOM,          28.0, 1, SHOW_PLAY },
  [BTN_CROUCH]    = { "CROUCH",      KIND_HOLD,     IOSTOUCH_CROUCH,        29.0, 1, SHOW_PLAY },
  [BTN_USE]       = { "USE",         KIND_HOLD,     IOSTOUCH_USE,           29.0, 1, SHOW_PLAY },
  [BTN_JUMP]      = { "JUMP",        KIND_HOLD,     IOSTOUCH_JUMP,          31.0, 1, SHOW_PLAY },
  [BTN_BOMB]      = { "BOMB",        KIND_HOLD,     IOSTOUCH_BOMB,          30.0, 1, SHOW_PLAY },
  [BTN_NEXTWPN]   = { "NEXT\nWPN",   KIND_HOLD,     IOSTOUCH_NEXTWEAPON,    22.0, 0, SHOW_PLAY },
  [BTN_PREVWPN]   = { "PREV\nWPN",   KIND_HOLD,     IOSTOUCH_PREVWEAPON,    22.0, 0, SHOW_PLAY },
  [BTN_KEYBOARD]  = { "",            KIND_TAP,      IOSTOUCH_REQ_CONSOLE,   22.0, 0, SHOW_PLAY | SHOW_CONS },
  [BTN_QUICKSAVE] = { "QUICK\nSAVE", KIND_TAP,      IOSTOUCH_REQ_QUICKSAVE, 22.0, 0, SHOW_PLAY },
  [BTN_QUICKLOAD] = { "QUICK\nLOAD", KIND_HOLDLOAD, IOSTOUCH_REQ_QUICKLOAD, 22.0, 0, SHOW_PLAY },
  [BTN_MENU]      = { "MENU",        KIND_MENU,     IOSTOUCH_REQ_MENU,      22.0, 0, SHOW_PLAY | SHOW_PAUSE },
  [BTN_RESUME]    = { "RESUME",      KIND_TAP,      IOSTOUCH_REQ_RESUME,    44.0, 0, SHOW_PAUSE },
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
// than a tick, and they are reported as one press.
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

// Places every button on a W x H point screen with these safe-area insets,
// keeping clear of the HUD's score box, ammo row and unread messages box (in
// points) and of the camera cutout when it may be on the right. FIRE itself
// may cover the messages box's envelope icon; the count stays clear.
static void IOSTouch_LayoutButtons(double W, double H, double inLeft, double inTop, double inRight, double inBottom,
                                   int bCutoutMayBeRight, const IOSTouchRect *prScore, const IOSTouchRect *prAmmo,
                                   const IOSTouchRect *prMessages)
{
  const double left = fmax(inLeft, 8.0);
  const double right = W - fmax(inRight, 8.0);
  const double top = fmax(inTop, 8.0);
  const double bottom = H - fmax(inBottom, 8.0);

  // FIRE in the corner. On screens without a bottom inset (Home-button
  // iPhones, iPads) the ammo row reaches up to there: FIRE goes above it.
  const double FR = _aButtons[BTN_FIRE].radius;
  double fireX = right - 76, fireY = bottom - 58;
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
  // apart, so a press meant for QUICK LOAD can't land on QUICK SAVE -- and the
  // keyboard left of them (the game prints messages at the top left, and its
  // high score box is in the middle)
  _aButtons[BTN_KEYBOARD].x = right - 216;
  _aButtons[BTN_QUICKSAVE].x = right - 156;
  _aButtons[BTN_QUICKLOAD].x = right - 90;
  _aButtons[BTN_MENU].x = right - 24;
  const int aTopRight[] = { BTN_KEYBOARD, BTN_QUICKSAVE, BTN_QUICKLOAD, BTN_MENU };
  for (int i = 0; i < (int)(sizeof(aTopRight) / sizeof(aTopRight[0])); i++) {
    _aButtons[aTopRight[i]].y = top + 26;
  }
  // RESUME in the middle of the screen
  _aButtons[BTN_RESUME].x = (left + right) * 0.5;
  _aButtons[BTN_RESUME].y = (top + bottom) * 0.5;
}

// ------------------------------------------------------- main-thread state

typedef enum {
  ROLE_NONE = 0,
  ROLE_STICK,
  ROLE_LOOK,
  ROLE_BUTTON,
  ROLE_IGNORED, // not on a button while only buttons are live; ignored until it lifts
} IOSTouchRole;

typedef struct {
  UITouch *__unsafe_unretained touch; // only compared, never used after it ends
  IOSTouchRole role;
  int button;
  CGPoint origin;
  CGPoint last;
  CFTimeInterval tDown; // when the touch began (QUICK LOAD: began on the button)
  int bFired;           // QUICK LOAD: already asked for this touch
} IOSTouchSlot;

static IOSTouchSlot _aSlots[IOSTOUCH_MAX_TOUCHES];
static int _aButtonHeld[IOSTOUCH_NUM_BUTTONS]; // touches on each button
static int _bStickActive = 0;
static float _fStickX = 0.0f, _fStickY = 0.0f; // -1..1 of the radius, screen axes
static int _iMode = IOSTOUCH_HIDDEN;
static int _iRequests = 0;                       // IOSTOUCH_REQ_* not handed out yet
static IOSTouchHud _hud;                         // the latest HUD state...
static IOSTouchRect _rScoreFrac, _rAmmoFrac, _rMessagesFrac;      // ...and the last boxes it showed (fractions)
// What the current layout was made for
static IOSTouchRect _rLayoutScore, _rLayoutAmmo, _rLayoutMessages; // in points
static int _iLayoutCutoutRight = -1;

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

// ---------------------------------------------------------------- overlay view

@interface IOSTouchOverlay : UIView {
  UIView *stickBase;
  UIView *stickKnob;
  UILabel *aButtonViews[IOSTOUCH_NUM_BUTTONS];
  CAShapeLayer *loadRing; // QUICK LOAD's hold progress
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

    // Ring that fills while QUICK LOAD is held
    CGFloat r = _aButtons[BTN_QUICKLOAD].radius;
    loadRing = [CAShapeLayer layer];
    loadRing.frame = CGRectMake(0, 0, r * 2, r * 2);
    loadRing.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(r, r) radius:r - 2.5
                                               startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES].CGPath;
    loadRing.fillColor = [UIColor clearColor].CGColor;
    loadRing.strokeColor = [UIColor colorWithRed:0.47 green:0.78 blue:1.0 alpha:0.95].CGColor;
    loadRing.lineWidth = 3.0;
    loadRing.strokeEnd = 0.0;
    [aButtonViews[BTN_QUICKLOAD].layer addSublayer:loadRing];

    // The keyboard button shows the keyboard symbol
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    UIImage *kb = [UIImage systemImageNamed:@"keyboard" withConfiguration:cfg];
    if (kb) {
      NSTextAttachment *att = [[NSTextAttachment alloc] init];
      att.image = [kb imageWithTintColor:[UIColor colorWithWhite:1.0 alpha:0.85] renderingMode:UIImageRenderingModeAlwaysOriginal];
      aButtonViews[BTN_KEYBOARD].attributedText = [NSAttributedString attributedStringWithAttachment:att];
    }
    else {
      aButtonViews[BTN_KEYBOARD].text = @"TYPE";
    }
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
  _rLayoutAmmo = IOSTouch_RectInPoints(&_rAmmoFrac, W, H);
  _rLayoutMessages = IOSTouch_RectInPoints(&_rMessagesFrac, W, H);
  _iLayoutCutoutRight = IOSTouch_CutoutMayBeRight(self);
  IOSTouch_LayoutButtons(W, H, in.left, in.top, in.right, in.bottom, _iLayoutCutoutRight,
                         &_rLayoutScore, &_rLayoutAmmo, &_rLayoutMessages);

  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    aButtonViews[i].center = CGPointMake(_aButtons[i].x, _aButtons[i].y);
  }
}

// Whether a button shows now
- (int)isShown:(int)button
{
  if (!(_aButtons[button].iShowIn & (1 << _iMode))) return 0;
  if (button == BTN_ZOOM) return _hud.bValid && _hud.bSniper;
  if (button == BTN_BOMB) return _hud.bValid && _hud.ctBombs > 0;
  return 1;
}

// Closest showing button the touch is on (with a little forgiveness), so a
// touch in the gap between two buttons picks the nearer one rather than the
// first listed.
- (int)buttonAt:(CGPoint)p
{
  int best = -1;
  CGFloat bestDist = 0;
  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    const IOSTouchButton *b = &_aButtons[i];
    if (aButtonViews[i].hidden) continue;
    CGFloat d = hypot(p.x - b->x, p.y - b->y);
    if (d <= b->radius + 6.0 && (best < 0 || d - b->radius < bestDist)) {
      best = i;
      bestDist = d - b->radius;
    }
  }
  return best;
}

- (int)isPoint:(CGPoint)p onButton:(int)button
{
  const IOSTouchButton *b = &_aButtons[button];
  return hypot(p.x - b->x, p.y - b->y) <= b->radius + 6.0;
}

- (void)hideStick
{
  stickBase.hidden = YES;
  stickKnob.hidden = YES;
}

- (void)refreshButtonLooks
{
  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    UILabel *l = aButtonViews[i];
    const int bShown = [self isShown:i];
    if (l.hidden == bShown) l.hidden = !bShown;
    const int bHeld = _aButtonHeld[i] != 0;
    l.backgroundColor = [UIColor colorWithWhite:(bHeld ? 1.0 : 0.0) alpha:(bHeld ? 0.30 : 0.22)];
    // The keyboard stands out in yellow, at full strength, while the console is open
    const int bOn = (i == BTN_KEYBOARD && _iMode == IOSTOUCH_CONSOLE);
    l.alpha = (bHeld || bOn) ? 1.0 : IOSTOUCH_IDLE_ALPHA;
    if (i != BTN_FIRE) {
      l.layer.borderColor = bOn ? [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:0.95].CGColor
                                : [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    }
  }
}

- (void)setLoadProgress:(CGFloat)progress
{
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  loadRing.strokeEnd = progress;
  [CATransaction commit];
}

- (void)updateStickVisual:(IOSTouchSlot *)s
{
  stickBase.center = s->origin;
  stickKnob.center = CGPointMake(s->origin.x + _fStickX * IOSTOUCH_STICK_RADIUS,
                                 s->origin.y + _fStickY * IOSTOUCH_STICK_RADIUS);
  stickBase.hidden = NO;
  stickKnob.hidden = NO;
}

// The stick as movement: nothing inside the dead zone, full speed from
// IOSTOUCH_STICK_FULL of the radius out, in the direction it is pushed
- (void)setMoveFromStick
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

// ------------------------------------------------------------ touches

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  for (UITouch *t in touches) {
    int slot = -1;
    for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
      if (_aSlots[i].touch == nil) { slot = i; break; }
    }
    if (slot < 0) continue;

    CGPoint p = [t locationInView:self];
    IOSTouchSlot *s = &_aSlots[slot];
    memset(s, 0, sizeof(*s));
    s->touch = t;
    s->origin = p;
    s->last = p;
    s->tDown = CACurrentMediaTime();
    s->button = [self buttonAt:p];

    if (s->button >= 0) {
      s->role = ROLE_BUTTON;
      _aButtonHeld[s->button]++;
      if (_aButtons[s->button].kind == KIND_MENU) _iRequests |= _aButtons[s->button].ulAction;
    }
    else if (_iMode != IOSTOUCH_GAMEPLAY) {
      s->role = ROLE_IGNORED; // only the buttons are live (console open, paused)
    }
    else if (p.x < self.bounds.size.width * IOSTOUCH_STICK_ZONE && !_bStickActive) {
      s->role = ROLE_STICK;
      _bStickActive = 1;
      _fStickX = _fStickY = 0.0f;
      [self updateStickVisual:s];
    }
    else {
      s->role = ROLE_LOOK;
    }
  }
  IOSTouch_SetHeld(IOSTouch_HeldButtons(), 0);
  [self refreshButtonLooks];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  float fLookX = 0.0f, fLookY = 0.0f;
  int bStickMoved = 0;
  for (UITouch *t in touches) {
    for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
      IOSTouchSlot *s = &_aSlots[i];
      if (s->touch != t) continue;
      CGPoint p = [t locationInView:self];

      if (s->role == ROLE_STICK) {
        float dx = (p.x - s->origin.x) / IOSTOUCH_STICK_RADIUS;
        float dy = (p.y - s->origin.y) / IOSTOUCH_STICK_RADIUS;
        float len = sqrtf(dx * dx + dy * dy);
        if (len > 1.0f) { dx /= len; dy /= len; }
        _fStickX = dx;
        _fStickY = dy;
        [self updateStickVisual:s];
        bStickMoved = 1;
      }
      else if (s->role == ROLE_LOOK ||
               (s->role == ROLE_BUTTON && _aButtons[s->button].bLookWhileHeld)) {
        fLookX += (float)(p.x - s->last.x) * IOSTOUCH_LOOK_SCALE_X;
        fLookY += (float)(p.y - s->last.y) * IOSTOUCH_LOOK_SCALE_Y;
      }
      // QUICK LOAD only counts while the finger stays on it
      if (s->role == ROLE_BUTTON && s->button == BTN_QUICKLOAD && ![self isPoint:p onButton:BTN_QUICKLOAD]) {
        s->tDown = CACurrentMediaTime();
      }
      s->last = p;
    }
  }
  if (bStickMoved) [self setMoveFromStick];
  if (fLookX != 0.0f || fLookY != 0.0f) {
    os_unfair_lock_lock(&_lock);
    if (_bReading) {
      _fLookX += fLookX;
      _fLookY += fLookY;
    }
    os_unfair_lock_unlock(&_lock);
  }
}

// bCancelled: iOS took the touch away (a call, a system gesture...) -- release
// whatever it held, but don't treat it as a finished tap
- (void)endTouches:(NSSet<UITouch *> *)touches cancelled:(int)bCancelled
{
  unsigned int ulLifted = 0;
  for (UITouch *t in touches) {
    for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
      IOSTouchSlot *s = &_aSlots[i];
      if (s->touch != t) continue;
      CGPoint p = [t locationInView:self];
      if (s->role == ROLE_BUTTON) {
        const IOSTouchButton *b = &_aButtons[s->button];
        if (_aButtonHeld[s->button] > 0) _aButtonHeld[s->button]--;
        // A tap so quick that no game tick saw it held still counts as one press
        if (!bCancelled && b->kind == KIND_HOLD && _aButtonHeld[s->button] == 0) {
          ulLifted |= b->ulAction;
        }
        // These act when the finger lifts on the button, so a slip onto one
        // can be dragged off again
        if (!bCancelled && b->kind == KIND_TAP && [self isPoint:p onButton:s->button]) {
          _iRequests |= b->ulAction;
        }
        if (s->button == BTN_QUICKLOAD) [self setLoadProgress:0.0];
      }
      else if (s->role == ROLE_STICK) {
        _bStickActive = 0;
        _fStickX = _fStickY = 0.0f;
        [self hideStick];
        [self setMoveFromStick];
      }
      memset(s, 0, sizeof(*s));
    }
  }
  IOSTouch_SetHeld(IOSTouch_HeldButtons(), ulLifted);
  [self refreshButtonLooks];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self endTouches:touches cancelled:0]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self endTouches:touches cancelled:1]; }

// Once per frame while shown: QUICK LOAD's hold, and the context buttons
- (void)tick
{
  CFTimeInterval now = CACurrentMediaTime();
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    IOSTouchSlot *s = &_aSlots[i];
    if (!s->touch || s->role != ROLE_BUTTON || s->button != BTN_QUICKLOAD || s->bFired) continue;
    CGFloat progress = (CGFloat)((now - s->tDown) / IOSTOUCH_QUICKLOAD_HOLD);
    if (progress >= 1.0) {
      s->bFired = 1;
      [self setLoadProgress:0.0];
      _iRequests |= IOSTOUCH_REQ_QUICKLOAD;
    }
    else {
      [self setLoadProgress:progress];
    }
  }

  // BOMB says how many there are
  const int ctBombs = _hud.bValid ? _hud.ctBombs : 0;
  if (ctBombs != ctBombsShown) {
    ctBombsShown = ctBombs;
    UILabel *l = aButtonViews[BTN_BOMB];
    l.text = ctBombs > 1 ? [NSString stringWithFormat:@"BOMB\n%d", ctBombs] : @"BOMB";
    l.font = [UIFont boldSystemFontOfSize:(ctBombs > 1 ? 10 : 13)];
  }
  // ZOOM and BOMB come and go
  if (aButtonViews[BTN_ZOOM].hidden == [self isShown:BTN_ZOOM] || aButtonViews[BTN_BOMB].hidden == [self isShown:BTN_BOMB]) {
    [self refreshButtonLooks];
  }
}

- (void)resetAll
{
  memset(_aSlots, 0, sizeof(_aSlots));
  memset(_aButtonHeld, 0, sizeof(_aButtonHeld));
  _bStickActive = 0;
  _fStickX = _fStickY = 0.0f;
  _iRequests = 0;
  IOSTouch_ResetShared(_iMode == IOSTOUCH_GAMEPLAY && !self.hidden && self.superview != nil);
  [self hideStick];
  [self setLoadProgress:0.0];
  [self refreshButtonLooks];
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
// never end)
static void IOSTouch_SetMode(int iMode)
{
  const int iOld = _iMode;
  _iMode = iMode;
  if (_pOverlay) {
    _pOverlay.hidden = (iMode == IOSTOUCH_HIDDEN);
    [_pOverlay resetAll];
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

int IOSTouch_Update(void *pSDLWindow, int iMode, const IOSTouchHud *pHud)
{
  // what was asked for since the last frame (the main loop checks it still fits)
  const int iRequests = _iRequests;
  _iRequests = 0;

  // the player may have closed the keyboard themselves, which stops text events too
  if (SDL_EventState(SDL_TEXTINPUT, SDL_QUERY) == SDL_DISABLE) {
    SDL_EventState(SDL_TEXTINPUT, SDL_ENABLE);
  }

  if (pHud) {
    _hud = *pHud;
    IOSTouch_KeepRect(&_rScoreFrac, pHud->afScore);
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

  if (iMode != IOSTOUCH_HIDDEN) {
    // The HUD is laid out again on resize and HUD scale changes. Turning the
    // phone the other way up changes neither the size nor the insets, but
    // moves the cutout to the other side.
    CGSize sz = _pOverlay.bounds.size;
    IOSTouchRect rScore = IOSTouch_RectInPoints(&_rScoreFrac, sz.width, sz.height);
    IOSTouchRect rAmmo = IOSTouch_RectInPoints(&_rAmmoFrac, sz.width, sz.height);
    IOSTouchRect rMessages = IOSTouch_RectInPoints(&_rMessagesFrac, sz.width, sz.height);
    if (!IOSTouch_SameRect(&rScore, &_rLayoutScore) || !IOSTouch_SameRect(&rAmmo, &_rLayoutAmmo)
        || !IOSTouch_SameRect(&rMessages, &_rLayoutMessages)
        || IOSTouch_CutoutMayBeRight(_pOverlay) != _iLayoutCutoutRight) {
      [_pOverlay setNeedsLayout];
    }
    [_pOverlay tick];
  }
  return iRequests;
}

void IOSTouch_Hide(void)
{
  if (_iMode != IOSTOUCH_HIDDEN) IOSTouch_SetMode(IOSTOUCH_HIDDEN);
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
