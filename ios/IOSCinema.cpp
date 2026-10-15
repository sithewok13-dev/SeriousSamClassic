// The touch controls' CAMERA: the cinematic burst. See IOSCinema.h.

#include <GameMP/StdAfx.h>
#include "IOSPhotoCam.h"
#include "IOSFreeze.h"
#include "IOSFreezeCam.h"
#include "IOSCapture.h"
#include "IOSPhotos.h"
#include "IOSCinema.h"

// The plan, worked out once as the freeze's first frame is drawn (all
// geometry, no extra frames drawn), as the Jedi Knight port's:
//
// What it turns round. The most interesting thing the player faces: an
// enemy, a shot in flight or an explosion, near the way they face, in their
// sight and not too far (IOSCINEMA_SUBJECT_*). An enemy close to the player:
// both of them, round the middle between them. Nothing: the player (a hero
// shot). Else as Action Freeze picked (a point straight ahead).
//
// The photos. The first is exactly what the player saw. The other four go
// round what it turns round, from far enough out to frame it, looking down
// on it a little: one thing, starting from the player's side of it; two,
// round the side view of them (from the player's side), so both stay in the
// photo; the player alone, round their front.
//
// Which way, how far round. Arcs from the widest (_afSweep) down, each way,
// rising a little or more: the widest where the camera has room at each
// photo's place and a clear view of what it turns round from each. None like
// that: the best of them if it is good enough, else the five from where it
// is, zooming in a little each time.
#define IOSCINEMA_SUBJECT_RANGE 25.0f  // (metres)
#define IOSCINEMA_SUBJECT_ANGLE 50.0f  // (degrees off the way the player faces)
#define IOSCINEMA_PAIR_RANGE    10.0f  // (both in the photo, nearer than this)
#define IOSCINEMA_DIST_MIN       3.0f  // (how far out it draws back, at least...)
#define IOSCINEMA_DIST_MAX       8.0f  // (...and at most)
#define IOSCINEMA_HERO_DIST      3.0f
#define IOSCINEMA_PITCH_HIGH   -30.0f  // (the start: looking down at most this much...)
#define IOSCINEMA_PITCH_LOW      5.0f  // (...and up at most this much)
#define IOSCINEMA_PITCH_END    -40.0f  // (with the rise, looking down at most this much at the end)
#define IOSCINEMA_HERO_PITCH   -12.0f
static const FLOAT _afSweep[] = { 90.0f, 70.0f, 50.0f, 35.0f, 20.0f };
static const FLOAT _afRise[] = { -14.0f, -6.0f }; // (less: a camera higher up, looking down)
#define IOSCINEMA_ROOM        0.7f  // (at each place, at least this part of the distance wanted)
#define IOSCINEMA_ROOM_LEAST  0.4f  // (the best of the rest, used if at least this...)
#define IOSCINEMA_SEEN_LEAST  3     // (...and in clear view from this many of the four places)
#define IOSCINEMA_ZOOM_STEP   1.15f // (the fallback: zoomed in this much more each photo)
#define IOSCINEMA_NEAR_HEAD   0.7f  // (as IOSFreeze's: the player's body isn't drawn)
// The first photo waits this long (the buttons hidden, a frame drawn
// frozen); the others are taken a frame apart; the last stays on screen
// IOSCINEMA_SHOW; a photo not taken IOSCINEMA_GIVEUP after it was due ends it
#define IOSCINEMA_SETTLE 0.1
#define IOSCINEMA_SHOW   0.5
#define IOSCINEMA_GIVEUP 3.0

enum { SUBJECT_PAIR = 0, SUBJECT_ONE, SUBJECT_HERO, SUBJECT_KEPT };

static int _iState = IOSCINEMA_IDLE;
static int _bPlanned = 0;
static int _ctTaken = 0, _bAsked = 0;
static double _tStart = 0, _tStage = 0, _tLast = 0;
static FLOAT _fSweep = 0.0f, _fRise = 0.0f;
static int _iDir = 1;
static int _bZoomOnly = 0, _bOrbit = 0;
static FLOAT _fArcMiddle = 0.0f;
static FLOAT _fDist0 = 0.0f, _fDist1 = 0.0f;
static FLOAT3D _vFocus(0, 0, 0);
static FLOAT _fBaseYaw = 0.0f, _fBasePitch = 0.0f;
static FLOAT _fMinDist = 0.3f; // (how near the focus the camera may come: out of what it turns round)
static CEntity *_apenSubject[2] = { NULL, NULL };
static FLOAT3D _vEye(0, 0, 0);
static ANGLE3D _aView(0, 0, 0);

// Who can stand in the way of the view (enemies alive, and the player):
// where their middle is and how big
#define IOSCINEMA_MAX_PEOPLE 256
typedef struct {
  CEntity *pen;
  FLOAT3D vMid;
  FLOAT fR;
} IOSCinemaPerson;
static IOSCinemaPerson _aPeople[IOSCINEMA_MAX_PEOPLE];
static int _ctPeople = 0;

static void IOSCinema_Middle(CEntity *pen, FLOAT3D &vMid, FLOAT &fR)
{
  FLOATaabbox3D box;
  pen->GetBoundingBox(box);
  vMid = box.Center();
  const FLOAT3D vSize = box.Size();
  fR = Max(0.5f * sqrt(vSize(1) * vSize(1) + vSize(3) * vSize(3)), 0.3f);
}

static FLOAT IOSCinema_ArcAt(int k)
{
  return _bOrbit ? (FLOAT)(k - 1) / (IOSCINEMA_SHOTS - 2) : (FLOAT)k / (IOSCINEMA_SHOTS - 1);
}

static FLOAT IOSCinema_DistAt(FLOAT t)
{
  return _fDist0 + (_fDist1 - _fDist0) * t;
}

static FLOAT IOSCinema_Heading(const FLOAT3D &v)
{
  FLOAT3D d = v;
  d(2) = 0.0f;
  if (d.Length() < 0.001f) return _aView(1);
  d.Normalize();
  ANGLE3D a;
  DirectionVectorToAngles(d, a);
  return a(1);
}

// Whether the focus is in clear view from vPos: no wall, and nobody else
// across the line (nor the camera inside anyone)
static int IOSCinema_Sees(const FLOAT3D &vPos)
{
  FLOAT3D v = _vFocus - vPos;
  const FLOAT fLen = v.Length();
  if (fLen < 0.01f) return 1;
  if (IOSPhotoCam_ClearDist(vPos, _vFocus) < fLen - 0.3f) return 0;
  v /= fLen;
  CEntity *penPlayer = IOSPhotoCam_Player();
  for (int i = 0; i < _ctPeople; i++) {
    const IOSCinemaPerson &p = _aPeople[i];
    FLOAT3D d = p.vMid - vPos;
    // (the player's body isn't drawn with the camera right by their head)
    if (p.pen == penPlayer && (_vEye - vPos).Length() < IOSCINEMA_NEAR_HEAD) continue;
    if (d.Length() < p.fR * 1.2f) return 0;
    if (p.pen == _apenSubject[0] || p.pen == _apenSubject[1]) continue;
    const FLOAT fAlong = d % v;
    if (fAlong < 0.3f || fAlong > fLen - 0.3f) continue;
    d -= v * fAlong;
    if (d.Length() < p.fR * 1.1f) return 0;
  }
  return 1;
}

// The most interesting thing in view from the player's eyes: NULL if none
static CEntity *IOSCinema_PickSubject(FLOAT &fDist)
{
  FLOAT3D vFwd;
  AnglesToDirectionVector(ANGLE3D(_aView(1), _aView(2), 0.0f), vFwd);
  const FLOAT fCosMax = cos(IOSCINEMA_SUBJECT_ANGLE * PI / 180.0f);
  CEntity *penBest = NULL;
  FLOAT fBestScore = 0.0f;
  CEntity *penPlayer = IOSPhotoCam_Player();
  FOREACHINDYNAMICCONTAINER(_pNetwork->ga_World.wo_cenEntities, CEntity, iten) {
    CEntity *pen = &*iten;
    if (pen == penPlayer || pen->GetRenderType() != CEntity::RT_MODEL) continue;
    FLOAT fBonus;
    if (IsDerivedFromClass(pen, "Enemy Base") && (pen->GetFlags() & ENF_ALIVE)) fBonus = 0.2f;
    else if (IsOfClass(pen, "BasicEffect")) fBonus = 0.25f;
    else if (IsOfClass(pen, "Projectile")) fBonus = 0.15f;
    else continue;
    FLOAT3D vMid;
    FLOAT fR;
    IOSCinema_Middle(pen, vMid, fR);
    FLOAT3D v = vMid - _vEye;
    const FLOAT fD = v.Length();
    if (fD < 0.3f || fD > IOSCINEMA_SUBJECT_RANGE) continue;
    const FLOAT c = (v % vFwd) / fD;
    if (c < fCosMax) continue;
    if (!IOSPhotoCam_Clear(_vEye, vMid, fR)) continue; // (behind a wall)
    const FLOAT fAng = acos(Min(c, 1.0f)) * 180.0f / PI;
    const FLOAT fScore = (1.0f - fAng / IOSCINEMA_SUBJECT_ANGLE) * 0.55f + (1.0f - fD / IOSCINEMA_SUBJECT_RANGE) * 0.25f + fBonus;
    if (fScore > fBestScore) {
      fBestScore = fScore;
      penBest = pen;
      fDist = fD;
    }
  }
  return penBest;
}

// One arc, tried without moving: the least room at its four later places
// (-1: the camera can't be at one), and from how many the focus is in view
static FLOAT IOSCinema_TryArc(int iDir, FLOAT fSweep, FLOAT fRise, int &ctSeen)
{
  FLOAT fLeast = 1.0f;
  ctSeen = 0;
  for (int k = 1; k < IOSCINEMA_SHOTS; k++) {
    const FLOAT t = IOSCinema_ArcAt(k);
    const FLOAT fWant = IOSCinema_DistAt(t);
    FLOAT3D vPos;
    const FLOAT d = IOSFreeze_ProbeAt(_vFocus, _fBaseYaw + iDir * fSweep * (t - _fArcMiddle), _fBasePitch + fRise * t, fWant,
                                      _fMinDist, vPos);
    if (d < 0.0f) return -1.0f;
    fLeast = Min(fLeast, d / fWant);
    if (IOSCinema_Sees(vPos)) ctSeen++;
  }
  return fLeast;
}

static void IOSCinema_ChoosePath(void)
{
  const int ctSweeps = (int)(sizeof(_afSweep) / sizeof(_afSweep[0]));
  const int ctRises = (int)(sizeof(_afRise) / sizeof(_afRise[0]));
  FLOAT fBestScore = -1.0f, fBestSweep = 0.0f, fBestRise = 0.0f, fBestRoom = -1.0f;
  int iBestDir = 1, ctBestSeen = 0;
  for (int s = 0; s < ctSweeps; s++) {
    // the widest arc where every place has room and a clear view...
    FLOAT fOkRoom = -1.0f, fOkRise = 0.0f;
    int iOkDir = 1;
    for (int r = 0; r < ctRises; r++) {
      // (not looking down too steeply by the end)
      FLOAT fRise = _afRise[r];
      if (_bOrbit && _fBasePitch + fRise < IOSCINEMA_PITCH_END) fRise = IOSCINEMA_PITCH_END - _fBasePitch;
      if (fRise > 0.0f) fRise = 0.0f;
      for (int iDir = 1; iDir >= -1; iDir -= 2) {
        int ctSeen = 0;
        const FLOAT fRoom = IOSCinema_TryArc(iDir, _afSweep[s], fRise, ctSeen);
        if (fRoom < 0.0f) continue;
        if (fRoom >= IOSCINEMA_ROOM && ctSeen == IOSCINEMA_SHOTS - 1 && fRoom > fOkRoom + 0.05f) {
          fOkRoom = fRoom;
          fOkRise = fRise;
          iOkDir = iDir;
        }
        // (...else the best of the rest: in view first, then room, then wider)
        const FLOAT fScore = ctSeen * 0.5f + fRoom + _afSweep[s] / 90.0f * 0.3f;
        if (fScore > fBestScore) {
          fBestScore = fScore;
          fBestSweep = _afSweep[s];
          fBestRise = fRise;
          iBestDir = iDir;
          fBestRoom = fRoom;
          ctBestSeen = ctSeen;
        }
      }
    }
    if (fOkRoom >= 0.0f) {
      _fSweep = _afSweep[s];
      _fRise = fOkRise;
      _iDir = iOkDir;
      _bZoomOnly = 0;
      return;
    }
  }
  if (fBestRoom >= IOSCINEMA_ROOM_LEAST && ctBestSeen >= IOSCINEMA_SEEN_LEAST) {
    _fSweep = fBestSweep;
    _fRise = fBestRise;
    _iDir = iBestDir;
    _bZoomOnly = 0;
    return;
  }
  // nowhere good to go: from the player's view, zooming in
  _fSweep = _fRise = 0.0f;
  _iDir = 1;
  _fDist1 = _fDist0;
  _bZoomOnly = 1;
}

// One plan (kind, what it turns round): 1 if it has somewhere good to go
static int IOSCinema_TryPlan(int iKind, CEntity *pen, FLOAT fDist, const FLOAT3D &vKeptFocus, FLOAT fKeptYaw,
                             FLOAT fKeptPitch, FLOAT fKeptDist, FLOAT fKeptMin)
{
  FLOAT fMin = fKeptMin;
  CEntity *penPlayer = IOSPhotoCam_Player();
  FLOAT3D vPlayerMid;
  FLOAT fPlayerR;
  IOSCinema_Middle(penPlayer, vPlayerMid, fPlayerR);
  FLOAT3D vFocus = vKeptFocus;
  FLOAT fDist1 = fKeptDist, fYaw = fKeptYaw, fPitch = fKeptPitch;
  _apenSubject[0] = _apenSubject[1] = NULL;
  _fArcMiddle = 0.0f;
  _bOrbit = 1;
  if (iKind == SUBJECT_PAIR) {
    // both: round the middle between them, far enough out to have them both
    // in the photo, side on to the line between them, on the player's side
    FLOAT3D vMid;
    FLOAT fR;
    IOSCinema_Middle(pen, vMid, fR);
    FLOAT3D v = vMid - vPlayerMid;
    const FLOAT fApart = v.Length();
    vFocus = vPlayerMid + v * 0.5f;
    const FLOAT fTall = tan(IOSPhotoCam_GetFov() * 0.5f * PI / 180.0f);
    fDist1 = (fApart * 0.5f + 0.8f) / (fTall * 1.4f);
    FLOAT3D vSide(-v(3), 0.0f, v(1));
    if (vSide % (_vEye - vFocus) < 0.0f) vSide = -vSide;
    fYaw = IOSCinema_Heading(-vSide);
    fPitch = -10.0f;
    _fArcMiddle = 0.5f;
    _apenSubject[0] = pen;
    _apenSubject[1] = penPlayer;
    fMin = 0.3f;
  }
  else if (iKind == SUBJECT_ONE) {
    // one: from the player's side of it
    FLOAT fR;
    IOSCinema_Middle(pen, vFocus, fR);
    fMin = fR + 0.45f;
    fDist1 = fDist;
    FLOAT3D v = vFocus - _vEye;
    if (v.Length() > 0.01f) {
      v.Normalize();
      ANGLE3D a;
      DirectionVectorToAngles(v, a);
      fYaw = a(1);
      fPitch = a(2);
    }
    _apenSubject[0] = pen;
  }
  else if (iKind == SUBJECT_HERO) {
    // the player: round their front
    FLOAT3D vFwd;
    AnglesToDirectionVector(ANGLE3D(penPlayer->GetPlacement().pl_OrientationAngle(1), 0.0f, 0.0f), vFwd);
    vFocus = vPlayerMid;
    fMin = fPlayerR + 0.45f;
    fDist1 = IOSCINEMA_HERO_DIST;
    fYaw = IOSCinema_Heading(-vFwd);
    fPitch = IOSCINEMA_HERO_PITCH;
    _fArcMiddle = 0.5f;
    _apenSubject[0] = penPlayer;
  }
  else {
    // as Action Freeze picked, on from the player's view
    _bOrbit = 0;
    _apenSubject[0] = pen;
    _apenSubject[1] = penPlayer;
  }
  if (iKind != SUBJECT_KEPT) {
    fDist1 = Clamp(fDist1, IOSCINEMA_DIST_MIN, IOSCINEMA_DIST_MAX);
    fPitch = Clamp(fPitch, IOSCINEMA_PITCH_HIGH, IOSCINEMA_PITCH_LOW);
  }
  FLOAT3D vPos;
  if (IOSFreeze_ProbeAt(vFocus, fYaw, fPitch, fDist1, fMin, vPos) < 0.0f) return 0;
  _fMinDist = fMin;
  _vFocus = vFocus;
  _fBaseYaw = fYaw;
  _fBasePitch = fPitch;
  _fDist0 = _fDist1 = fDist1;
  IOSCinema_ChoosePath();
  return !_bZoomOnly;
}

// What it turns round and how: both, else the one, else the player, else as
// Action Freeze picked; else zooming in from the player's view
static void IOSCinema_Plan(void)
{
  IOSPhotoCam_PlayerView(_vEye, _aView);
  FLOAT3D vKeptFocus;
  FLOAT fKeptYaw, fKeptPitch, fKeptDist, fKeptMin;
  IOSFreeze_GetOrbit(vKeptFocus, fKeptYaw, fKeptPitch, fKeptDist, fKeptMin);
  _fMinDist = fKeptMin;
  _vFocus = vKeptFocus;
  _fBaseYaw = fKeptYaw;
  _fBasePitch = fKeptPitch;
  _fDist0 = _fDist1 = fKeptDist;
  _bZoomOnly = 0;
  // (who can be in the way)
  _ctPeople = 0;
  CEntity *penPlayer = IOSPhotoCam_Player();
  FOREACHINDYNAMICCONTAINER(_pNetwork->ga_World.wo_cenEntities, CEntity, iten) {
    CEntity *pen = &*iten;
    if (_ctPeople >= IOSCINEMA_MAX_PEOPLE) break;
    if (pen != penPlayer && !(IsDerivedFromClass(pen, "Enemy Base") && (pen->GetFlags() & ENF_ALIVE))) continue;
    _aPeople[_ctPeople].pen = pen;
    IOSCinema_Middle(pen, _aPeople[_ctPeople].vMid, _aPeople[_ctPeople].fR);
    _ctPeople++;
  }
  FLOAT fDist = 0.0f;
  CEntity *pen = IOSCinema_PickSubject(fDist);
  int aiKind[4], ct = 0;
  if (pen != NULL && IsDerivedFromClass(pen, "Enemy Base")) {
    FLOAT3D vMid, vPlayerMid;
    FLOAT fR;
    IOSCinema_Middle(pen, vMid, fR);
    IOSCinema_Middle(penPlayer, vPlayerMid, fR);
    if ((vMid - vPlayerMid).Length() < IOSCINEMA_PAIR_RANGE) aiKind[ct++] = SUBJECT_PAIR;
  }
  if (pen != NULL) aiKind[ct++] = SUBJECT_ONE;
  aiKind[ct++] = SUBJECT_HERO;
  aiKind[ct++] = SUBJECT_KEPT;
  for (int i = 0; i < ct; i++) {
    if (IOSCinema_TryPlan(aiKind[i], pen, fDist, vKeptFocus, fKeptYaw, fKeptPitch, fKeptDist, fKeptMin)) return;
  }
  // (nowhere good for any: zooming in from the player's view)
  _bZoomOnly = 1;
  _fSweep = _fRise = 0.0f;
}

// The camera to photo k's place on the arc (a place it can't go: that photo
// from the last place)
static void IOSCinema_MoveTo(int k)
{
  if (_bZoomOnly) {
    IOSFreeze_Zoom(IOSCINEMA_ZOOM_STEP);
    return;
  }
  const FLOAT t = IOSCinema_ArcAt(k);
  IOSFreeze_SetOrbit(_vFocus, _fBaseYaw + _iDir * _fSweep * (t - _fArcMiddle), _fBasePitch + _fRise * t, IOSCinema_DistAt(t),
                     _fMinDist);
}

extern "C" int IOSCinema_Start(double now)
{
  if (_iState != IOSCINEMA_IDLE) return IOSCINEMA_CANT;
  // (room for all five in the capture budget first: it never waits frozen)
  if (IOSCapture_IsPending() || !IOSCapture_HasRoom(IOSCAPTURE_CLEAN, IOSCINEMA_SHOTS)) return IOSCINEMA_BUSY;
  if (!IOSFreeze_Begin()) return IOSCINEMA_CANT;
  IOSFreeze_SetSmooth(0); // (the photos land exactly where planned)
  _bPlanned = 0;
  _ctTaken = 0;
  _bAsked = 0;
  _tStart = _tStage = _tLast = now;
  _iState = IOSCINEMA_TAKING;
  IOSPhotos_SetBatch(1); // (one message for them all, numbered names)
  return IOSCINEMA_STARTED;
}

extern "C" int IOSCinema_Tick(double now)
{
  if (_iState == IOSCINEMA_IDLE) return IOSCINEMA_IDLE;
  _tLast = now;
  if (!IOSFreeze_IsActive()) {
    IOSCinema_Stop(); // (ended from elsewhere)
    return _iState;
  }
  if (!_bPlanned) {
    if (!IOSFreeze_IsReady()) {
      // (not drawn yet; it would be by now if the game drew at all)
      if (now - _tStart >= IOSCINEMA_GIVEUP) {
        IOSCinema_Stop();
        IOS_ShowCameraMessage("Couldn't take the photos");
      }
      return _iState;
    }
    // As the freeze's first frame was drawn: the plan, then back to the
    // player's view for the first photo
    FLOAT3D vEye;
    ANGLE3D aRot;
    IOSPhotoCam_GetPlace(vEye, aRot);
    const FLOAT fFov = IOSPhotoCam_GetFov();
#ifdef IOS_CAMERA_RIG_DEBUG
    const CTimerValue tv0 = _pTimer->GetHighPrecisionTimer();
#endif
    IOSCinema_Plan();
#ifdef IOS_CAMERA_RIG_DEBUG
    printf("RIGDBG cinema plan %.1f ms\n", (_pTimer->GetHighPrecisionTimer() - tv0).GetSeconds() * 1000.0);
#endif
    IOSPhotoCam_Place(vEye, aRot);
    IOSPhotoCam_SetFov(fFov);
    IOSPhotoCam_SetHidePlayer(1);
    _bPlanned = 1;
    _tStage = now;
  }
  if (_iState == IOSCINEMA_SHOWING) {
    if (now - _tStage >= IOSCINEMA_SHOW) IOSCinema_Stop();
    return _iState;
  }
  // taken (a frame read it), or given up on by the capture
  if (_bAsked && !IOSCapture_IsPending()) {
    _bAsked = 0;
    _ctTaken++;
    _tStage = now;
    if (_ctTaken >= IOSCINEMA_SHOTS) {
      _iState = IOSCINEMA_SHOWING;
      return _iState;
    }
    IOSCinema_MoveTo(_ctTaken); // (drawn there in the next frame)
  }
  if (!_bAsked) {
    const int bDue = _ctTaken > 0 || now - _tStage >= IOSCINEMA_SETTLE;
    if (bDue && IOSCapture_Request(IOSCAPTURE_CLEAN, IOSCAPTURE_MODE_BURST)) {
      _bAsked = 1;
      _tStage = now;
    }
  }
  if (now - _tStage >= IOSCINEMA_GIVEUP + (_ctTaken ? 0.0 : IOSCINEMA_SETTLE)) {
    const int taken = _ctTaken;
    IOSCinema_Stop();
    char msg[64];
    if (taken) snprintf(msg, sizeof(msg), "Took %d of %d photos", taken, IOSCINEMA_SHOTS);
    else snprintf(msg, sizeof(msg), "Couldn't take the photos");
    IOS_ShowCameraMessage(msg);
  }
  return _iState;
}

extern "C" void IOSCinema_Stop(void)
{
  if (_iState == IOSCINEMA_IDLE) return;
  if (_bAsked && IOSCapture_IsPending()) IOSCapture_Cancel();
  _bAsked = 0;
  _iState = IOSCINEMA_IDLE;
  _apenSubject[0] = _apenSubject[1] = NULL;
  IOSFreeze_End();
  IOSCapture_NoteFreeze(_tLast - _tStart);
  IOSPhotos_SetBatch(0);
}

extern "C" int IOSCinema_IsActive(void)
{
  return _iState != IOSCINEMA_IDLE;
}

extern "C" int IOSCinema_NumTaken(void)
{
  return _ctTaken;
}
