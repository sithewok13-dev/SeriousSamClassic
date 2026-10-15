// The touch controls' CAMERA: Action Freeze. See IOSFreeze.h.

#include <GameMP/StdAfx.h>
#include "IOSPhotoCam.h"
#include "IOSFreeze.h"
#include "IOSFreezeCam.h"

// Lengths are metres, angles degrees. The camera turns round a focus: what
// the player looks at -- the nearest enemy, shot, blast or item within
// IOSFREEZE_FOCUS_REACH times its size of the line of sight, between
// IOSFREEZE_FOCUS_MIN and IOSFREEZE_FOCUS_MAX ahead and before the first wall
// (IOSFREEZE_WALL_GAP short of it) -- or else a point IOSFREEZE_FOCUS_AHEAD
// ahead. It starts exactly where the player's eyes are. It never comes nearer
// the focus than IOSFREEZE_DIST_MIN, keeps a ball of IOSFREEZE_CAM_ROOM round
// it clear of the level, and tips at most IOSFREEZE_PITCH_MAX up or down.
// Pushed in by a wall it finds the nearest place that fits by
// IOSFREEZE_STEPS_IN steps in and IOSFREEZE_FIT_HALVINGS halvings; with
// smoothing on it glides back out IOSFREEZE_EASE_OUT of the way a frame, once
// it hasn't been pushed in for IOSFREEZE_HOLD_IN frames. The player's own
// body is left out while the camera is within IOSFREEZE_NEAR_HEAD of their
// head (and until it first moves, from the player's eyes).
#define IOSFREEZE_FOCUS_MAX 15.0f
#define IOSFREEZE_FOCUS_MIN 0.8f
#define IOSFREEZE_FOCUS_AHEAD 4.0f
#define IOSFREEZE_FOCUS_REACH 1.5f
#define IOSFREEZE_WALL_GAP 0.2f
#define IOSFREEZE_DIST_MIN 0.3f
#define IOSFREEZE_DIST_MAX 60.0f
#define IOSFREEZE_CAM_ROOM 0.15f
#define IOSFREEZE_PITCH_MAX 80.0f
#define IOSFREEZE_STEPS_IN 12
#define IOSFREEZE_FIT_HALVINGS 7
#define IOSFREEZE_EASE_OUT 0.25f
#define IOSFREEZE_HOLD_IN 12
#define IOSFREEZE_NEAR_HEAD 0.7f

static int _bActive = 0, _bReady = 0;
static FLOAT3D _vFocus(0, 0, 0);
static FLOAT _fYaw = 0.0f, _fPitch = 0.0f;
static FLOAT _fWanted = 1.0f;   // how far from the focus it would be
static FLOAT _fShown = 1.0f;    // how far it is (nearer where a wall is in the way)
static int _bSmooth = 0;
static int _ctHeldIn = 0;       // frames since it was last pushed in
static int _bInsideMe = 0;      // started from the player's eyes, not moved yet
static FLOAT _fMinDist = IOSFREEZE_DIST_MIN; // (round a thing: out of it)

static FLOAT3D IOSFreeze_Dir(FLOAT fYaw, FLOAT fPitch)
{
  FLOAT3D d;
  AnglesToDirectionVector(ANGLE3D(fYaw, fPitch, 0.0f), d);
  return d;
}

static int IOSFreeze_Fits(const FLOAT3D &vFocus, const FLOAT3D &vCam)
{
  return IOSPhotoCam_RoomAt(vFocus, vCam, IOSFREEZE_CAM_ROOM);
}

FLOAT IOSFreeze_ProbeAt(const FLOAT3D &vFocus, FLOAT fYaw, FLOAT fPitch, FLOAT fDist, FLOAT fMinDist, FLOAT3D &vPos)
{
  const FLOAT3D vDir = IOSFreeze_Dir(fYaw, fPitch);
  const FLOAT fWant = Max(fDist, fMinDist);
  // as far as the level lets it, short of a wall (and never nearer than the least)
  FLOAT d0 = IOSPhotoCam_ClearDist(vFocus, vFocus - vDir * fWant);
  if (d0 < fWant - 0.01f) d0 -= IOSFREEZE_WALL_GAP; // (a wall in the way)
  else d0 = fWant;
  if (d0 < fMinDist) return -1.0f;
  if (IOSFreeze_Fits(vFocus, vFocus - vDir * d0)) {
    vPos = vFocus - vDir * d0;
    return d0;
  }
  // nearer, in steps, then between the last that fit and the first that didn't
  FLOAT fFit = -1.0f, fNoFit = d0;
  for (int k = 1; k <= IOSFREEZE_STEPS_IN; k++) {
    const FLOAT d = fMinDist + (d0 - fMinDist) * (1.0f - (FLOAT)k / IOSFREEZE_STEPS_IN);
    if (IOSFreeze_Fits(vFocus, vFocus - vDir * d)) {
      fFit = d;
      break;
    }
    fNoFit = d;
  }
  if (fFit < 0.0f) {
    // (nowhere nearer: in a crowd, maybe further out, past whoever is in the
    // way, as far as the level lets it)
    const FLOAT fFar = IOSPhotoCam_ClearDist(vFocus, vFocus - vDir * IOSFREEZE_DIST_MAX) - IOSFREEZE_WALL_GAP;
    for (int k = 1; k <= IOSFREEZE_STEPS_IN; k++) {
      const FLOAT d = d0 + (FLOAT)k * Max(d0, 1.0f) * 0.25f;
      if (d > fFar) break;
      if (IOSFreeze_Fits(vFocus, vFocus - vDir * d)) {
        vPos = vFocus - vDir * d;
        return d;
      }
    }
    return -1.0f;
  }
  for (int h = 0; h < IOSFREEZE_FIT_HALVINGS; h++) {
    const FLOAT d = (fFit + fNoFit) * 0.5f;
    if (IOSFreeze_Fits(vFocus, vFocus - vDir * d)) fFit = d;
    else fNoFit = d;
  }
  vPos = vFocus - vDir * fFit;
  return fFit;
}

// The camera where the orbit puts it (and whether the player's body shows)
static void IOSFreeze_Place(void)
{
  const FLOAT3D vDir = IOSFreeze_Dir(_fYaw, _fPitch);
  const FLOAT3D vCam = _vFocus - vDir * _fShown;
  IOSPhotoCam_Place(vCam, ANGLE3D(_fYaw, _fPitch, 0.0f));
  FLOAT3D vEye;
  ANGLE3D aView;
  IOSPhotoCam_PlayerView(vEye, aView);
  IOSPhotoCam_SetHidePlayer(_bInsideMe || (vCam - vEye).Length() < IOSFREEZE_NEAR_HEAD);
}

// Puts the camera at this orbit: 0 (nothing changed) if it has nowhere to go
static int IOSFreeze_Go(const FLOAT3D &vFocus, FLOAT fYaw, FLOAT fPitch, FLOAT fWanted, int bExact)
{
  FLOAT3D vPos;
  const FLOAT d = IOSFreeze_ProbeAt(vFocus, fYaw, fPitch, fWanted, _fMinDist, vPos);
  if (d < 0.0f) return 0;
  _vFocus = vFocus;
  _fYaw = fYaw;
  _fPitch = fPitch;
  _fWanted = fWanted;
  if (bExact || !_bSmooth || d < _fShown) {
    // coming in is at once (a wall); going out glides, with smoothing on
    if (d < _fShown - 0.001f) _ctHeldIn = 0;
    _fShown = d;
  }
  else {
    _fShown = Min(_fShown, d);
  }
  IOSFreeze_Place();
  return 1;
}

// As the first frame of it is drawn: the focus, and the camera at the
// player's eyes looking at it
static int IOSFreeze_Prepare(int iW, int iH)
{
  (void)iW;
  (void)iH;
  FLOAT3D vEye;
  ANGLE3D aView;
  IOSPhotoCam_PlayerView(vEye, aView);
  IOSPhotoCam_SetFov(IOSPhotoCam_GameFov());
  const FLOAT3D vFwd = IOSFreeze_Dir(aView(1), aView(2));
  // the first wall ahead, and the nearest thing on the line of sight before it
  const FLOAT fWall = IOSPhotoCam_ClearDist(vEye, vEye + vFwd * IOSFREEZE_FOCUS_MAX) - IOSFREEZE_WALL_GAP;
  FLOAT fFocus = Min(IOSFREEZE_FOCUS_AHEAD, fWall);
  FLOAT fBest = 1e9f, fBestR = 0.0f;
  CEntity *penPlayer = IOSPhotoCam_Player();
  FOREACHINDYNAMICCONTAINER(_pNetwork->ga_World.wo_cenEntities, CEntity, iten) {
    CEntity *pen = &*iten;
    if (pen == penPlayer || pen->GetRenderType() != CEntity::RT_MODEL || pen->GetModelObject() == NULL) continue;
    const int bEnemy = IsDerivedFromClass(pen, "Enemy Base") && (pen->GetFlags() & ENF_ALIVE);
    const int bThing = IsOfClass(pen, "Projectile") || IsOfClass(pen, "BasicEffect") || IsDerivedFromClass(pen, "Item");
    if (!bEnemy && !bThing) continue;
    FLOATaabbox3D box;
    pen->GetBoundingBox(box);
    const FLOAT3D vMid = box.Center();
    const FLOAT fAlong = (vMid - vEye) % vFwd;
    if (fAlong < IOSFREEZE_FOCUS_MIN || fAlong > fWall || fAlong >= fBest) continue;
    const FLOAT fOff = (vMid - (vEye + vFwd * fAlong)).Length();
    const FLOAT fSize = Max(box.Size().Length() * 0.5f, 0.2f);
    if (fOff > IOSFREEZE_FOCUS_REACH * fSize) continue;
    fBest = fAlong;
    fBestR = 0.5f * sqrt(box.Size()(1) * box.Size()(1) + box.Size()(3) * box.Size()(3));
  }
  if (fBest < 1e8f) fFocus = fBest;
  fFocus = Max(fFocus, IOSFREEZE_DIST_MIN);
  // (round a thing, the camera keeps out of it: it backs off as it first moves)
  _fMinDist = Max(IOSFREEZE_DIST_MIN, fBestR + IOSFREEZE_CAM_ROOM + 0.3f);
  _vFocus = vEye + vFwd * fFocus;
  _fYaw = aView(1);
  _fPitch = Clamp(aView(2), -IOSFREEZE_PITCH_MAX, IOSFREEZE_PITCH_MAX);
  _fWanted = _fShown = fFocus;
  _ctHeldIn = IOSFREEZE_HOLD_IN;
  _bInsideMe = 1;
  // (exactly the player's view: from the eyes)
  IOSPhotoCam_Place(vEye, ANGLE3D(aView(1), aView(2), 0.0f));
  IOSPhotoCam_SetHidePlayer(1);
  _bReady = 1;
  return 1;
}

extern "C" int IOSFreeze_Begin(void)
{
  if (_bActive || IOSPhotoCam_IsActive()) return 0;
  _bReady = 0;
  _bSmooth = 0;
  if (!IOSPhotoCam_Begin(IOSFreeze_Prepare)) return 0;
  _bActive = 1;
  return 1;
}

extern "C" int IOSFreeze_Orbit(float yawDeg, float pitchDeg)
{
  if (!_bActive || !_bReady) return 1;
  const FLOAT fPitch = Clamp(_fPitch + pitchDeg, -IOSFREEZE_PITCH_MAX, IOSFREEZE_PITCH_MAX);
  FLOAT fYaw = (FLOAT)fmod(_fYaw + yawDeg, 360.0f);
  if (!IOSFreeze_Go(_vFocus, fYaw, fPitch, Max(_fWanted, _fMinDist), 0)) return 0;
  _bInsideMe = 0;
  IOSFreeze_Place();
  return 1;
}

extern "C" void IOSFreeze_Pan(float right, float down)
{
  if (!_bActive || !_bReady) return;
  // as far across as the screen's height at the focus
  const FLOAT fH = 2.0f * Max(_fShown, IOSFREEZE_DIST_MIN) * tan(IOSPhotoCam_GetFov() * 0.5f * PI / 180.0f);
  FLOATmatrix3D m;
  MakeRotationMatrixFast(m, ANGLE3D(_fYaw, _fPitch, 0.0f));
  const FLOAT3D vRight(m(1, 1), m(2, 1), m(3, 1)), vUp(m(1, 2), m(2, 2), m(3, 2));
  // (what is seen follows the fingers: the camera goes the other way)
  FLOAT3D vMove = (vRight * -right + vUp * down) * fH;
  const FLOAT fLen = vMove.Length();
  if (fLen < 0.0001f) return;
  const FLOAT fFree = IOSPhotoCam_ClearDist(_vFocus, _vFocus + vMove) - IOSFREEZE_WALL_GAP;
  if (fFree <= 0.0f) return;
  if (fFree < fLen) vMove *= fFree / fLen;
  if (IOSFreeze_Go(_vFocus + vMove, _fYaw, _fPitch, Max(_fWanted, _fMinDist), 0)) _bInsideMe = 0;
  IOSFreeze_Place();
}

extern "C" void IOSFreeze_Zoom(float factor)
{
  if (!_bActive || !_bReady || factor <= 0.0f) return;
  const FLOAT fHalf = IOSPhotoCam_GetFov() * 0.5f * PI / 180.0f;
  IOSPhotoCam_SetFov(2.0f * atan(tan(fHalf) / factor) * 180.0f / PI);
}

extern "C" void IOSFreeze_SetSmooth(int bOn)
{
  _bSmooth = bOn != 0;
}

extern "C" void IOSFreeze_Frame(void)
{
  if (!_bActive || !_bReady || !_bSmooth) return;
  if (_ctHeldIn < IOSFREEZE_HOLD_IN) {
    _ctHeldIn++;
    return;
  }
  if (_fShown >= _fWanted - 0.005f) return;
  // gliding back out, as far as there is room
  FLOAT3D vPos;
  const FLOAT d = IOSFreeze_ProbeAt(_vFocus, _fYaw, _fPitch, _fWanted, _fMinDist, vPos);
  if (d <= _fShown + 0.005f) return;
  _fShown += (d - _fShown) * IOSFREEZE_EASE_OUT;
  IOSFreeze_Place();
}

extern "C" void IOSFreeze_End(void)
{
  if (!_bActive) return;
  _bActive = _bReady = 0;
  IOSPhotoCam_End();
}

extern "C" int IOSFreeze_IsActive(void)
{
  return _bActive;
}

// ------------------------------------------------------------ for IOSCinema

int IOSFreeze_IsReady(void)
{
  return _bActive && _bReady;
}

void IOSFreeze_GetOrbit(FLOAT3D &vFocus, FLOAT &fYaw, FLOAT &fPitch, FLOAT &fDist, FLOAT &fMinDist)
{
  fMinDist = _fMinDist;
  vFocus = _vFocus;
  fYaw = _fYaw;
  fPitch = _fPitch;
  fDist = _fWanted;
}

int IOSFreeze_SetOrbit(const FLOAT3D &vFocus, FLOAT fYaw, FLOAT fPitch, FLOAT fDist, FLOAT fMinDist)
{
  if (!_bActive || !_bReady) return 0;
  _fMinDist = Max(fMinDist, IOSFREEZE_DIST_MIN);
  fPitch = Clamp(fPitch, -IOSFREEZE_PITCH_MAX, IOSFREEZE_PITCH_MAX);
  if (!IOSFreeze_Go(vFocus, fYaw, fPitch, Clamp(fDist, _fMinDist, IOSFREEZE_DIST_MAX), 1)) return 0;
  _bInsideMe = 0;
  IOSFreeze_Place();
  return 1;
}
