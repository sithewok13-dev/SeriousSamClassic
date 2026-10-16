// The touch controls' CAMERA: a selfie. See IOSSelfie.h.

#include <GameMP/StdAfx.h>
#include "IOSPhotoCam.h"
#include "IOSStance.h"
#include "IOSSelfie.h"

// Lengths are metres (the player stands about 1.8 tall), angles degrees.
// People: enemies within IOSSELFIE_RANGE of the player, alive, in the
// player's sight; the nearest IOSSELFIE_MAX_PEOPLE of them. A photobomber
// (one selfie in IOSSELFIE_PHOTOBOMB_CHANCE) from further out, up to
// IOSSELFIE_PHOTOBOMB_RANGE, in the photo.
#define IOSSELFIE_RANGE 30.0f
#define IOSSELFIE_PHOTOBOMB_RANGE 45.0f
#define IOSSELFIE_PHOTOBOMB_CHANCE 6
// The camera: IOSSELFIE_FOV tall (degrees). Out from the player's eyes, at one
// of IOSSELFIE_NUM_DIRS headings round them (a bit to the side first, as a
// held-out arm), as near as IOSSELFIE_CAM_MIN and as far as IOSSELFIE_CAM_NEAR
// (a selfie: the player big in it, however big the crowd), or where there
// is no room for that, as far as IOSSELFIE_CAM_MAX, with a ball of IOSSELFIE_CAM_CLEARANCE round
// it clear of the level. Its height over the eyes: IOSSELFIE_LIFT, now and
// then IOSSELFIE_LIFT_UP or IOSSELFIE_LIFT_DOWN; or held up high,
// IOSSELFIE_LIFT_HIGH or _HIGHER, to see over a crowd (a little less good). One in IOSSELFIE_TILT_CHANCE photos tilted up to
// IOSSELFIE_TILT_MAX.
#define IOSSELFIE_FOV 70.0f
#define IOSSELFIE_NUM_DIRS 16
#define IOSSELFIE_CAM_MIN 0.6f
#define IOSSELFIE_CAM_NEAR 2.8f
#define IOSSELFIE_CAM_MAX 12.0f
#define IOSSELFIE_CAM_CLEARANCE 0.25f
#define IOSSELFIE_LIFT 0.15f
#define IOSSELFIE_LIFT_UP 0.6f
#define IOSSELFIE_LIFT_DOWN (-0.25f)
#define IOSSELFIE_LIFT_HIGH 1.2f
#define IOSSELFIE_LIFT_HIGHER 2.5f
#define IOSSELFIE_TILT_CHANCE 3
#define IOSSELFIE_TILT_MAX 6.0f
// Never looking down more steeply than IOSSELFIE_PITCH_DOWN_MAX (degrees):
// held up high, the camera stands further back instead (from right above, a
// crowd is a heap of heads with the player lost in it)
#define IOSSELFIE_PITCH_DOWN_MAX 35.0f
// Enemies nearer the camera than the player are left out of the photo (put
// back as it ends), as a held-out phone sees past them: those more than
// IOSSELFIE_FRONT_MARGIN nearer it than the player, or within
// IOSSELFIE_LENS_CLEAR of the lens; and those no more than
// IOSSELFIE_BESIDE further than the player whose bodies are over the
// player in the frame. The player is the nearest in it, and clear.
#define IOSSELFIE_FRONT_MARGIN 0.3f
#define IOSSELFIE_BESIDE 0.5f
#define IOSSELFIE_LENS_CLEAR 1.5f
// Two posed people whose bodies overlap by this much (of their sizes added
// up) are crowded: they stand calmly, rather than swing their arms through
// each other
#define IOSSELFIE_CROWDED 0.8f
// What fits: a head within these fractions of the frame's half width and
// half height from its middle (up, down); the player's (near the middle)
// within the second set. The nearest IOSSELFIE_FACES_CLEAR faces must be in
// the frame and clear; the further people count for less, the camera's
// distance against it a little.
#define IOSSELFIE_FIT_X 0.88f
#define IOSSELFIE_FIT_UP 0.80f
#define IOSSELFIE_FIT_DOWN 0.85f
#define IOSSELFIE_FIT_PLAYER_X 0.60f
#define IOSSELFIE_FIT_PLAYER_Y 0.55f
#define IOSSELFIE_FACES_CLEAR 3
#define IOSSELFIE_DIST_COST 0.25f
#define IOSSELFIE_CLUTTER_COST 12.0f
#define IOSSELFIE_CENTRE_X 0.35f
#define IOSSELFIE_CENTRE_Y 0.40f
// A head's size for hiding one behind another (of the person's height), and
// the margin round it (radians)
#define IOSSELFIE_HEAD_SIZE 0.12f
#define IOSSELFIE_HEAD_MARGIN 0.02f
// Poses: a small turn either way from facing the camera; one person in
// IOSSELFIE_TURN_CHANCE of 100 turned three-quarters (IOSSELFIE_TURN_MIN to
// _MAX); the player turned IOSSELFIE_PHONE_TURN away from the phone's
// side. One selfie in IOSSELFIE_GROUP_CHANCE all strike the same kind of
// pose, one in IOSSELFIE_RARE_CHANCE something unexpected happens.
#define IOSSELFIE_TURN_SMALL 7.0f
#define IOSSELFIE_TURN_CHANCE 45
#define IOSSELFIE_TURN_MIN 20.0f
#define IOSSELFIE_TURN_MAX 35.0f
#define IOSSELFIE_PHONE_TURN 20.0f
#define IOSSELFIE_GROUP_CHANCE 5
#define IOSSELFIE_RARE_CHANCE 20
// Shots, blasts and debris nearer the camera than a face and within its
// size of the line to it are left out of the photo
// (room for up to IOSSELFIE_MAX_PEOPLE_LIMIT, the player and a photobomber;
// IOSSelfie_SetMaxPeople sets how many: IOSSELFIE_MAX_PEOPLE unless set)
#define IOSSELFIE_MAX_PERSONS (IOSSELFIE_MAX_PEOPLE_LIMIT + 2)

typedef struct {
  CEntityPointer pen;
  int bPlayer;
  FLOAT fDist;          // from the player
  FLOAT3D vHead, vMid;
  FLOAT fHeight, fHeadR, fBodyR; // (how big a head and a body are, as seen from anywhere)
  int bInFrame;         // in the photo (posed)
  int bPhotobomb;
  // as it was
  CPlacement3D pl;
  FLOATmatrix3D mRot;
  IOSStanceSaved anim;
  IOSStanceSaved animBody;   // (the player: the body; the base model is the legs)
  CPlacement3D plView, plLastView;
} IOSSelfiePerson;

enum { RARE_NONE = 0, RARE_STARE, RARE_OBLIVIOUS, RARE_ALLEYES };

static int _bActive = 0, _bPosed = 0, _bFailed = 0;
static IOSSelfiePerson _aPeople[IOSSELFIE_MAX_PERSONS]; // [0]: the player
static int _ctPeople = 0;
static FLOAT3D _vCam(0, 0, 0);
static FLOAT _fLift = IOSSELFIE_LIFT;
static int _bPhoneLeft = 0;
static int _ctMaxPeople = IOSSELFIE_MAX_PEOPLE;
// Everything that can stand in front of a face: every enemy near the player
// (posing or not), where its head and middle are and how big
#define IOSSELFIE_MAX_BLOCKERS 256
typedef struct {
  CEntity *pen;
  FLOAT3D vHead, vMid;
  FLOAT fHeadR, fBodyR;
} IOSSelfieBlocker;
static IOSSelfieBlocker _aBlockers[IOSSELFIE_MAX_BLOCKERS];
static int _ctBlockers = 0;

// ------------------------------------------------------------ geometry

// Where a model's head and middle are, how tall it is, and how big its
// head and body are seen from anywhere (as drawn now)
static void IOSSelfie_Measure(CEntity *pen, FLOAT3D &vHead, FLOAT3D &vMid, FLOAT &fHeight, FLOAT &fHeadR, FLOAT &fBodyR)
{
  FLOATaabbox3D box(FLOAT3D(-0.5f, 0.0f, -0.5f), FLOAT3D(0.5f, 1.8f, 0.5f));
  CModelObject *pmo = pen->GetModelObject();
  if (pen->GetRenderType() == CEntity::RT_MODEL && pmo != NULL) {
    pmo->GetCurrentFrameBBox(box);
    box.StretchByVector(pmo->mo_Stretch);
  }
  const FLOATmatrix3D &m = pen->GetRotationMatrix();
  const FLOAT3D vPos = pen->GetPlacement().pl_PositionVector;
  const FLOAT3D c = box.Center();
  const FLOAT3D vSize = box.Size();
  fHeight = Max(vSize(2), 0.3f);
  vMid = vPos + c * m;
  vHead = vPos + FLOAT3D(c(1), box.minvect(2) + fHeight * 0.85f, c(3)) * m;
  // (generous: posed, it may swing its arms, lean, open its jaws)
  const FLOAT fWide = Max(vSize(1), vSize(3));
  fBodyR = Max(0.5f * Max(fWide, 0.6f * fHeight), 0.2f);
  fHeadR = Max(Min(0.35f * fWide, 0.2f * fHeight), 0.12f);
}

// Heading towards v from vFrom (degrees, as the game's)
static FLOAT IOSSelfie_HeadingTo(const FLOAT3D &vFrom, const FLOAT3D &v)
{
  FLOAT3D d = v - vFrom;
  d(2) = 0.0f;
  if (d.Length() < 0.001f) return 0.0f;
  d.Normalize();
  ANGLE3D a;
  DirectionVectorToAngles(d, a);
  return a(1);
}

static FLOAT3D IOSSelfie_Flat(FLOAT fHeading)
{
  FLOAT3D d;
  AnglesToDirectionVector(ANGLE3D(fHeading, 0.0f, 0.0f), d);
  return d;
}

// A camera at vCam looking at vAt: its axes (right, up, forward)
typedef struct {
  FLOAT3D vPos, vRight, vUp, vFwd;
  FLOAT fTanX, fTanY;
  ANGLE3D aRot;
} IOSSelfieView;

static void IOSSelfie_MakeView(IOSSelfieView &v, const FLOAT3D &vCam, const FLOAT3D &vAt, FLOAT fTilt)
{
  FLOAT3D d = vAt - vCam;
  if (d.Length() < 0.001f) d = FLOAT3D(0, 0, -1);
  d.Normalize();
  DirectionVectorToAngles(d, v.aRot);
  v.aRot(3) = fTilt;
  FLOATmatrix3D m;
  MakeRotationMatrixFast(m, v.aRot);
  v.vPos = vCam;
  v.vRight = FLOAT3D(m(1, 1), m(2, 1), m(3, 1));
  v.vUp = FLOAT3D(m(1, 2), m(2, 2), m(3, 2));
  v.vFwd = -FLOAT3D(m(1, 3), m(2, 3), m(3, 3));
  v.fTanY = tan(IOSSELFIE_FOV * 0.5f * PI / 180.0f);
  v.fTanX = v.fTanY * IOSPhotoCam_Aspect();
}

// Where a point is in the view: across and up as fractions of the half
// frame (beyond 1: outside), and how far in front (<= 0: behind)
static void IOSSelfie_Project(const IOSSelfieView &v, const FLOAT3D &p, FLOAT &fX, FLOAT &fY, FLOAT &fZ)
{
  const FLOAT3D d = p - v.vPos;
  fZ = d % v.vFwd;
  if (fZ <= 0.05f) {
    fX = fY = 99.0f;
    return;
  }
  fX = (d % v.vRight) / fZ / v.fTanX;
  fY = (d % v.vUp) / fZ / v.fTanY;
}

static int IOSSelfie_InFrame(const IOSSelfieView &v, const IOSSelfiePerson &p)
{
  FLOAT x, y, z;
  IOSSelfie_Project(v, p.vHead, x, y, z);
  if (z <= 0.05f) return 0;
  if (p.bPlayer) return fabs(x) <= IOSSELFIE_FIT_PLAYER_X && fabs(y) <= IOSSELFIE_FIT_PLAYER_Y;
  return fabs(x) <= IOSSELFIE_FIT_X && y <= IOSSELFIE_FIT_UP && y >= -IOSSELFIE_FIT_DOWN;
}

// Whether an enemy (its middle and size) is nearer a camera at vCam than the
// player, or level with them and over them, so left out of the photo from
// there (IOSSELFIE_FRONT_MARGIN, IOSSELFIE_BESIDE)
static int IOSSelfie_InFront(const FLOAT3D &vCam, const FLOAT3D &vMid, FLOAT fBodyR)
{
  const IOSSelfiePerson &me = _aPeople[0];
  FLOAT3D d = vMid - vCam;
  const FLOAT fD = d.Length();
  const FLOAT fPlayer = (me.vMid - vCam).Length();
  if (fD < IOSSELFIE_LENS_CLEAR || fD < fPlayer - IOSSELFIE_FRONT_MARGIN) return 1;
  if (fD >= fPlayer + IOSSELFIE_BESIDE) return 0;
  d /= fD;
  const FLOAT3D apv[2] = { me.vHead, me.vMid };
  const FLOAT afR[2] = { me.fHeadR, me.fBodyR };
  for (int k = 0; k < 2; k++) {
    FLOAT3D dp = apv[k] - vCam;
    const FLOAT fDp = dp.Length();
    if (fDp < 0.01f) continue;
    dp /= fDp;
    if (acos(Clamp(d % dp, -1.0f, 1.0f)) < fBodyR / fD + afR[k] / fDp) return 1;
  }
  return 0;
}

// Whether person i's face is seen from the camera: nothing of the level in
// the way, and nobody nearer over it (anyone near: posing, or not; but not
// those left out of the photo, IOSSelfie_InFront)
static int IOSSelfie_FaceClear(const FLOAT3D &vCam, int i)
{
  const IOSSelfiePerson &p = _aPeople[i];
  if (!IOSPhotoCam_Clear(vCam, p.vHead, p.fHeadR)) return 0;
  FLOAT3D di = p.vHead - vCam;
  const FLOAT fDi = di.Length();
  if (fDi < 0.01f) return 0;
  di /= fDi;
  for (int j = 0; j < _ctBlockers + 1; j++) {
    // (the blockers, and the player: not one of them)
    IOSSelfieBlocker bPlayer;
    const IOSSelfieBlocker *b = &bPlayer;
    if (j < _ctBlockers) {
      b = &_aBlockers[j];
    }
    else {
      bPlayer.pen = _aPeople[0].pen;
      bPlayer.vHead = _aPeople[0].vHead;
      bPlayer.vMid = _aPeople[0].vMid;
      bPlayer.fHeadR = _aPeople[0].fHeadR;
      bPlayer.fBodyR = _aPeople[0].fBodyR;
    }
    if (b->pen == (CEntity *)p.pen) continue;
    if (j < _ctBlockers && IOSSelfie_InFront(vCam, b->vMid, b->fBodyR)) continue;
    const FLOAT3D apv[2] = { b->vHead, b->vMid };
    const FLOAT afR[2] = { b->fHeadR, b->fBodyR };
    for (int k = 0; k < 2; k++) {
      FLOAT3D dj = apv[k] - vCam;
      const FLOAT fDj = dj.Length();
      if (fDj < 0.01f || fDj >= fDi - 0.1f) continue; // (only what is nearer)
      dj /= fDj;
      const FLOAT fAng = acos(Clamp(di % dj, -1.0f, 1.0f));
      if (fAng < afR[k] / fDj + IOSSELFIE_HEAD_MARGIN) return 0;
    }
  }
  return 1;
}

// How much of the frame things nearer the camera than the player cover
// (their bodies, roughly: 1 is the whole frame), but for those left out
static FLOAT IOSSelfie_Clutter(const IOSSelfieView &v)
{
  const FLOAT fPlayer = (_aPeople[0].vHead - v.vPos).Length();
  FLOAT fCover = 0.0f;
  for (int j = 0; j < _ctBlockers; j++) {
    const IOSSelfieBlocker &b = _aBlockers[j];
    if (IOSSelfie_InFront(v.vPos, b.vMid, b.fBodyR)) continue;
    FLOAT x, y, z;
    IOSSelfie_Project(v, b.vMid, x, y, z);
    if (z <= 0.05f || z >= fPlayer) continue;
    // (its size across the frame, as a fraction of the half frame)
    const FLOAT rx = b.fBodyR / z / v.fTanX, ry = b.fBodyR / z / v.fTanY;
    const FLOAT ox = Clamp(Min(x + rx, 1.0f) - Max(x - rx, -1.0f), 0.0f, 2.0f);
    const FLOAT oy = Clamp(Min(y + ry, 1.0f) - Max(y - ry, -1.0f), 0.0f, 2.0f);
    fCover += ox * oy / 4.0f;
  }
  return fCover;
}

// How good a photo from vCam is: the player in it and clear (else -1e9),
// then each other face in it and clear, the nearer to the player the more it
// counts; the nearest few missing count heavily against it; against it too,
// how much of it is hidden by things in front of the player, and a little
// the distance (a selfie is better near). With bFrameOnly, how good it
// could at best be (no rays).
static FLOAT IOSSelfie_Score(const IOSSelfieView &v, FLOAT fDist, int bFrameOnly)
{
  if (!IOSSelfie_InFrame(v, _aPeople[0])) return -1e9f;
  if (!bFrameOnly && !IOSSelfie_FaceClear(v.vPos, 0)) return -1e9f;
  FLOAT fScore = 3.0f - IOSSELFIE_DIST_COST * fDist;
  if (!bFrameOnly) fScore -= IOSSELFIE_CLUTTER_COST * IOSSelfie_Clutter(v);
  for (int i = 1; i < _ctPeople; i++) {
    const int bSeen = IOSSelfie_InFrame(v, _aPeople[i]) && !IOSSelfie_InFront(v.vPos, _aPeople[i].vMid, _aPeople[i].fBodyR)
                      && (bFrameOnly || IOSSelfie_FaceClear(v.vPos, i));
    if (bSeen) fScore += 1.0f / (1.0f + 0.12f * (i - 1));
    else if (i <= IOSSELFIE_FACES_CLEAR) fScore -= 4.0f;
  }
  return fScore;
}

// The point the camera looks at: the player's head and the others', the
// nearer counting for more
static FLOAT3D IOSSelfie_AimPoint(void)
{
  FLOAT3D v = _aPeople[0].vHead * 3.0f;
  FLOAT w = 3.0f;
  for (int i = 1; i < _ctPeople; i++) {
    const FLOAT wi = 1.0f / (1.0f + 0.25f * (i - 1));
    v += _aPeople[i].vHead * wi;
    w += wi;
  }
  return v / w;
}

// Whether an enemy will be left out of the photo from a camera at vCam (the
// camera may stand in it, IOSPhotoCam_SetLeftOut)
static int IOSSelfie_LeftOut(CEntity *pen, const FLOAT3D &vCam)
{
  for (int j = 0; j < _ctBlockers; j++) {
    if (_aBlockers[j].pen == pen) return IOSSelfie_InFront(vCam, _aBlockers[j].vMid, _aBlockers[j].fBodyR);
  }
  return 0;
}

// How steeply a camera at vCam looks down at v (degrees; up: below 0)
static FLOAT IOSSelfie_PitchDown(const FLOAT3D &vCam, const FLOAT3D &v)
{
  FLOAT3D d = v - vCam;
  const FLOAT fDown = -d(2);
  d(2) = 0.0f;
  return atan2(fDown, Max(d.Length(), 0.001f)) * 180.0f / PI;
}

// Finds where the camera goes: the best of the headings round the player,
// each at the nearest distance with the best photo. 0 if none sees the
// player.
static int IOSSelfie_PlaceCamera(void)
{
  const FLOAT3D vEye = _aPeople[0].vHead;
  // out from the player, on the other side from the people (alone: in
  // front of the player)
  FLOAT3D vGroup(0, 0, 0);
  FLOAT wGroup = 0.0f;
  for (int i = 1; i < _ctPeople && i <= 8; i++) {
    vGroup += _aPeople[i].vHead;
    wGroup += 1.0f;
  }
  FLOAT fAway;
  FLOAT3D vAway = vEye - (wGroup > 0 ? vGroup / wGroup : vEye);
  vAway(2) = 0.0f;
  if (vAway.Length() > 0.5f) {
    fAway = IOSSelfie_HeadingTo(FLOAT3D(0, 0, 0), vAway);
  }
  else {
    FLOAT3D vE;
    ANGLE3D aView;
    IOSPhotoCam_PlayerView(vE, aView);
    fAway = aView(1);
  }
  static const int aiSteps[IOSSELFIE_NUM_DIRS] = { 2, -2, 1, -1, 3, -3, 0, 4, -4, 5, -5, 6, -6, 7, -7, 8 };
  static const FLOAT afDist[] = { 0.6f, 0.8f, 1.0f, 1.3f, 1.7f, 2.2f, 2.8f, 3.6f, 4.6f, 6.0f, 7.5f, 9.5f, 12.0f, 16.0f };
  const int ctDist = (int)(sizeof(afDist) / sizeof(afDist[0]));
  const FLOAT3D vAt = IOSSelfie_AimPoint();
  FLOAT fBest = -1e8f;
  FLOAT3D vBest(0, 0, 0);
  static const FLOAT afLiftCost[3] = { 0.0f, 0.4f, 0.8f };
  IOSPhotoCam_SetLeftOut(IOSSelfie_LeftOut);
  // (near first; further only where nothing near will do)
  for (int iRound = 0; iRound < 2 && fBest <= -1e7f; iRound++) {
    const FLOAT fMax = iRound ? IOSSELFIE_CAM_MAX : IOSSELFIE_CAM_NEAR;
    for (int pass = 0; pass < 3; pass++) {
      const FLOAT fLift = (pass == 0) ? _fLift : ((pass == 1) ? IOSSELFIE_LIFT_HIGH : IOSSELFIE_LIFT_HIGHER);
      for (int k = 0; k < IOSSELFIE_NUM_DIRS; k++) {
        const FLOAT fHeading = fAway + aiSteps[k] * (360.0f / IOSSELFIE_NUM_DIRS) * (_bPhoneLeft ? -1.0f : 1.0f);
        const FLOAT3D vDir = IOSSelfie_Flat(fHeading);
        // the furthest the camera can go that way (the level in the way)
        const FLOAT3D vFar = vEye + vDir * IOSSELFIE_CAM_MAX + FLOAT3D(0, fLift, 0);
        const FLOAT fFree = IOSPhotoCam_ClearDist(vEye, vFar) - IOSSELFIE_CAM_CLEARANCE;
        for (int d = 0; d < ctDist && afDist[d] <= fMax; d++) {
          const FLOAT3D vCam = vEye + vDir * afDist[d] + FLOAT3D(0, fLift, 0);
          if ((vCam - vEye).Length() > fFree) break; // (and further that way)
          // (never looking down too steeply: at the people, nor at the
          // player, where a photo's aim is drawn towards them)
          if (IOSSelfie_PitchDown(vCam, vAt) > IOSSELFIE_PITCH_DOWN_MAX
              || IOSSelfie_PitchDown(vCam, vEye - FLOAT3D(0, 0.3f, 0)) > IOSSELFIE_PITCH_DOWN_MAX) continue;
          IOSSelfieView v;
          IOSSelfie_MakeView(v, vCam, vAt, 0.0f);
          // (what it could be at best, before casting any rays)
          if (IOSSelfie_Score(v, afDist[d], 1) - afLiftCost[pass] <= fBest + 0.001f) continue;
          if (!IOSPhotoCam_RoomAt(vEye, vCam, IOSSELFIE_CAM_CLEARANCE)) continue;
          const FLOAT fScore = IOSSelfie_Score(v, afDist[d], 0) - afLiftCost[pass];
          if (fScore > fBest + 0.001f) {
            fBest = fScore;
            vBest = vCam;
          }
        }
      }
      // (alone: no need to hold it up high)
      if (fBest > -1e7f && _ctPeople == 1) break;
    }
  }
  IOSPhotoCam_SetLeftOut(NULL);
  if (fBest <= -1e7f) return 0;
  _vCam = vBest;
  return 1;
}

// ------------------------------------------------------------ posing

// Turns a person to the given heading (keeping their pitch and banking)
static void IOSSelfie_Face(CEntity *pen, FLOAT fHeading)
{
  ANGLE3D a = pen->en_plPlacement.pl_OrientationAngle;
  a(1) = fHeading;
  pen->en_plPlacement.pl_OrientationAngle = a;
  MakeRotationMatrixFast(pen->en_mRotation, a);
}

// The player: turned to the camera, a little away from the phone's side,
// looking at the lens, posed (an arm up, the gun shown off, both arms out,
// looking about), standing
static void IOSSelfie_PosePlayer(void)
{
  IOSSelfiePerson &p = _aPeople[0];
  CPlayer *pl = (CPlayer *)&*p.pen;
  const FLOAT fToCam = IOSSelfie_HeadingTo(p.pl.pl_PositionVector, _vCam);
  const FLOAT fBody = fToCam + (_bPhoneLeft ? -IOSSELFIE_PHONE_TURN : IOSSELFIE_PHONE_TURN)
                      + (IOSStance_Rand01() - 0.5f) * 2.0f * IOSSELFIE_TURN_SMALL;
  IOSSelfie_Face(pl, fBody);
  // the head (the view, relative to the body) towards the lens
  FLOAT3D d = _vCam - p.vHead;
  if (d.Length() > 0.01f) {
    d.Normalize();
    ANGLE3D a;
    DirectionVectorToAngles(d, a);
    FLOAT fRel = a(1) - fBody;
    while (fRel > 180.0f) fRel -= 360.0f;
    while (fRel < -180.0f) fRel += 360.0f;
    pl->en_plViewpoint.pl_OrientationAngle = ANGLE3D(Clamp(fRel, -60.0f, 60.0f), Clamp(a(2), -50.0f, 50.0f), 0.0f);
    pl->en_plLastViewpoint.pl_OrientationAngle = pl->en_plViewpoint.pl_OrientationAngle;
  }
  CModelObject *pmo = pl->GetModelObject();
  if (pmo == NULL) return;
  INDEX iAnim, iFrame;
  // the legs: standing
  if (IOSStance_Find(pmo, "STAND", iAnim)) IOSStance_Hold(pmo, iAnim, 0);
  CAttachmentModelObject *pamo = pmo->GetAttachmentModel(0); // (the torso: the body)
  if (pamo == NULL) return;
  static const int aiWeights[IOSSTANCE_PLAYER_NUM] = { 5, 3, 1, 1 };
  int r = IOSStance_Rand(10), iPose = 0;
  while (iPose < IOSSTANCE_PLAYER_NUM - 1 && r >= aiWeights[iPose]) r -= aiWeights[iPose++];
  if (IOSStance_PickPlayer(&pamo->amo_moModelObject, iPose, iAnim, iFrame)
      || IOSStance_PickPlayer(&pamo->amo_moModelObject, IOSSTANCE_PLAYER_GUN, iAnim, iFrame)) {
    IOSStance_Hold(&pamo->amo_moModelObject, iAnim, iFrame);
  }
}

// Leaves shots, blasts and debris out of the photo where they are in front
// of a face in it
static void IOSSelfie_HideInFront(void)
{
  FOREACHINDYNAMICCONTAINER(_pNetwork->ga_World.wo_cenEntities, CEntity, iten) {
    CEntity *pen = &*iten;
    if (!IsOfClass(pen, "Projectile") && !IsOfClass(pen, "BasicEffect") && !IsOfClass(pen, "Debris")) continue;
    if (IOSPhotoCam_IsHidden(pen)) continue;
    const FLOAT3D vPos = pen->GetPlacement().pl_PositionVector;
    FLOAT3D dp = vPos - _vCam;
    const FLOAT fDp = dp.Length();
    if (fDp < 0.01f) {
      IOSPhotoCam_Hide(pen);
      continue;
    }
    dp /= fDp;
    for (int i = 0; i < _ctPeople; i++) {
      const IOSSelfiePerson &p = _aPeople[i];
      if (!p.bInFrame) continue;
      FLOAT3D dh = p.vHead - _vCam;
      const FLOAT fDh = dh.Length();
      if (fDh < 0.01f || fDp >= fDh) continue;
      dh /= fDh;
      const FLOAT fAng = acos(Clamp(dp % dh, -1.0f, 1.0f));
      if (fAng < p.fHeadR * 1.5f / fDh + 0.03f) {
        IOSPhotoCam_Hide(pen);
        break;
      }
    }
  }
}

// Whether a posed person (as drawn now) is in front of the player's face
static int IOSSelfie_OverPlayer(const IOSSelfiePerson &p)
{
  FLOAT3D vHead, vMid;
  FLOAT fHeight, fHeadR, fBodyR;
  IOSSelfie_Measure(p.pen, vHead, vMid, fHeight, fHeadR, fBodyR);
  FLOAT3D dp = _aPeople[0].vHead - _vCam;
  const FLOAT fDp = dp.Length();
  if (fDp < 0.01f) return 0;
  dp /= fDp;
  const FLOAT3D apv[2] = { vHead, vMid };
  const FLOAT afR[2] = { fHeadR, fBodyR };
  for (int k = 0; k < 2; k++) {
    FLOAT3D d = apv[k] - _vCam;
    const FLOAT fD = d.Length();
    if (fD < 0.01f || fD >= fDp - 0.1f) continue;
    d /= fD;
    if (acos(Clamp(d % dp, -1.0f, 1.0f)) < afR[k] / fD + IOSSELFIE_HEAD_MARGIN) return 1;
  }
  return 0;
}

// Anyone whose pose put them in front of the player's face poses
// otherwise: standing about first, then a few other poses at random, or
// as they were
static void IOSSelfie_ClearPlayersFace(int iOblivious)
{
  for (int i = 1; i < _ctPeople; i++) {
    IOSSelfiePerson &p = _aPeople[i];
    if (!p.bInFrame || i == iOblivious || p.pen == NULL || (p.pen->GetFlags() & ENF_DELETED)) continue;
    if (!IOSSelfie_OverPlayer(p)) continue;
    CModelObject *pmo = p.pen->GetModelObject();
    int bClear = 0;
    for (int t = 0; t < 4 && !bClear; t++) {
      INDEX iAnim, iFrame;
      if (IOSStance_Pick(pmo, t ? IOSStance_RandomKind() : IOSSTANCE_IDLE, iAnim, iFrame)) {
        IOSStance_Hold(pmo, iAnim, iFrame);
        bClear = !IOSSelfie_OverPlayer(p);
      }
    }
    if (!bClear) IOSStance_Restore(pmo, p.anim);
  }
}

// Everyone in the photo posed (afresh for each photo), the camera aimed at
// them all
static void IOSSelfie_Pose(void)
{
  // back as they were first: each pose starts clean
  for (int i = 1; i < _ctPeople; i++) {
    IOSSelfiePerson &p = _aPeople[i];
    if (p.pen == NULL || (p.pen->GetFlags() & ENF_DELETED)) continue;
    p.pen->en_plPlacement = p.pl;
    p.pen->en_mRotation = p.mRot;
    IOSStance_Restore(p.pen->GetModelObject(), p.anim);
  }
  // The camera: aimed at the middle of the faces in the photo (the heads a
  // little above the middle of it), now and then tilted; then everyone in
  // the frame so aimed is in it (as far as the first IOSSelfie_SetMaxPeople)
  FLOAT3D vSum(0, 0, 0);
  FLOAT ctSum = 0.0f;
  for (int i = 0; i < _ctPeople; i++) {
    if (i && !_aPeople[i].bInFrame) continue;
    vSum += _aPeople[i].vHead * (i ? 1.0f : 2.0f);
    ctSum += i ? 1.0f : 2.0f;
  }
  const FLOAT3D vAt = vSum / ctSum - FLOAT3D(0, 0.15f, 0);
  const FLOAT fTilt = IOSStance_Chance(IOSSELFIE_TILT_CHANCE) ? (IOSStance_Rand01() - 0.5f) * 2.0f * IOSSELFIE_TILT_MAX : 0.0f;
  // ...but the player near the middle: the aim drawn towards them as far as
  // that takes (their face in the middle IOSSELFIE_CENTRE_X across and
  // IOSSELFIE_CENTRE_Y up and down)
  IOSSelfieView v;
  for (int t = 0; t <= 10; t++) {
    const FLOAT f = t * 0.1f;
    IOSSelfie_MakeView(v, _vCam, vAt * (1.0f - f) + (_aPeople[0].vHead - FLOAT3D(0, 0.3f, 0)) * f, fTilt);
    FLOAT x, y, z;
    IOSSelfie_Project(v, _aPeople[0].vHead, x, y, z);
    if (z > 0.05f && fabs(x) <= IOSSELFIE_CENTRE_X && fabs(y) <= IOSSELFIE_CENTRE_Y) break;
  }
  IOSPhotoCam_Place(_vCam, v.aRot);
  for (int i = 1; i < _ctPeople; i++) {
    if (!_aPeople[i].bPhotobomb) {
      _aPeople[i].bInFrame = IOSSelfie_InFrame(v, _aPeople[i]) && _aPeople[i].fDist <= IOSSELFIE_RANGE
                             && !IOSPhotoCam_IsHidden(_aPeople[i].pen);
    }
  }

  int ctOthers = 0, iBomber = -1;
  for (int i = 1; i < _ctPeople; i++) {
    if (!_aPeople[i].bInFrame) continue;
    ctOthers++;
    if (_aPeople[i].bPhotobomb) iBomber = i;
  }
  // the whole group the same kind of pose, now and then; or something unexpected
  const int iGroupKind = (ctOthers >= 2 && IOSStance_Chance(IOSSELFIE_GROUP_CHANCE)) ? IOSStance_RandomKind() : -1;
  int iRare = RARE_NONE, iOblivious = -1;
  if (ctOthers >= 1 && IOSStance_Chance(IOSSELFIE_RARE_CHANCE)) {
    const int r = IOSStance_Rand(3);
    if (r == 0 && iBomber >= 0) iRare = RARE_STARE;            // everyone stares at the photobomber
    else if (r == 1 && ctOthers >= 2) iRare = RARE_OBLIVIOUS;  // one hasn't noticed the photo
    else iRare = RARE_ALLEYES;                                 // everyone stares at the player
    if (iRare == RARE_OBLIVIOUS) {
      int k = IOSStance_Rand(ctOthers);
      for (int i = 1; i < _ctPeople && iOblivious < 0; i++) {
        if (_aPeople[i].bInFrame && !_aPeople[i].bPhotobomb && k-- == 0) iOblivious = i;
      }
    }
  }
  for (int i = 1; i < _ctPeople; i++) {
    IOSSelfiePerson &p = _aPeople[i];
    if (!p.bInFrame || i == iOblivious || p.pen == NULL || (p.pen->GetFlags() & ENF_DELETED)) continue;
    CEntity *pen = p.pen;
    // crowded (another in the photo, or the player, close enough for poses
    // to cut through each other): standing calmly, turned only a little
    int bCrowded = 0;
    for (int j = 0; j < _ctPeople && !bCrowded; j++) {
      const IOSSelfiePerson &o = _aPeople[j];
      if (j == i || !(j == 0 || o.bInFrame)) continue;
      bCrowded = (o.vMid - p.vMid).Length() < IOSSELFIE_CROWDED * (o.fBodyR + p.fBodyR);
    }
    FLOAT3D vLook = _vCam;
    if (iRare == RARE_STARE && i != iBomber) vLook = _aPeople[iBomber].vHead;
    if (iRare == RARE_ALLEYES) vLook = _aPeople[0].vHead;
    FLOAT fHeading = IOSSelfie_HeadingTo(p.pl.pl_PositionVector, vLook)
                     + (IOSStance_Rand01() - 0.5f) * 2.0f * IOSSELFIE_TURN_SMALL;
    if (!p.bPhotobomb && !bCrowded && iRare == RARE_NONE && IOSStance_Rand(100) < IOSSELFIE_TURN_CHANCE) {
      const FLOAT fTurn = IOSSELFIE_TURN_MIN + IOSStance_Rand01() * (IOSSELFIE_TURN_MAX - IOSSELFIE_TURN_MIN);
      fHeading += IOSStance_Chance(2) ? fTurn : -fTurn;
    }
    IOSSelfie_Face(pen, fHeading);
    int iKind = (iGroupKind >= 0) ? iGroupKind : IOSStance_RandomKind();
    if (bCrowded) iKind = IOSSTANCE_IDLE;
    if (p.bPhotobomb) iKind = IOSStance_Chance(2) ? IOSSTANCE_ATTACK : IOSSTANCE_ANGER;
    INDEX iAnim, iFrame;
    CModelObject *pmo = pen->GetModelObject();
    if (IOSStance_Pick(pmo, iKind, iAnim, iFrame)) IOSStance_Hold(pmo, iAnim, iFrame);
  }
  IOSSelfie_PosePlayer();
  IOSSelfie_ClearPlayersFace(iOblivious);

  IOSSelfie_HideInFront();
}

// ------------------------------------------------------------ the selfie

// Who is in it: the player, then the enemies near them in their sight, the
// nearest first
static void IOSSelfie_FindPeople(CPlayer *pl)
{
  _ctPeople = 0;
  IOSSelfiePerson &me = _aPeople[_ctPeople++];
  me.pen = pl;
  me.bPlayer = 1;
  me.fDist = 0.0f;
  me.bPhotobomb = 0;
  FLOAT3D vEye;
  ANGLE3D aView;
  IOSPhotoCam_PlayerView(vEye, aView);
  IOSSelfie_Measure(pl, me.vHead, me.vMid, me.fHeight, me.fHeadR, me.fBodyR);
  me.vHead = vEye;
  me.fHeadR = 0.15f;
  me.fBodyR = 0.3f;

  typedef struct { CEntity *pen; FLOAT fDist; } Found;
  static Found aFound[512];
  int ctFound = 0;
  const FLOAT3D vPl = pl->GetPlacement().pl_PositionVector;
  FOREACHINDYNAMICCONTAINER(_pNetwork->ga_World.wo_cenEntities, CEntity, iten) {
    CEntity *pen = &*iten;
    if (ctFound >= 512) break;
    if (!IsDerivedFromClass(pen, "Enemy Base") || !(pen->GetFlags() & ENF_ALIVE) || pen->IsPredictor()) continue;
    if (pen->GetRenderType() != CEntity::RT_MODEL || pen->GetModelObject() == NULL || pen->en_penParent != NULL) continue;
    if (IsOfClass(pen, "CannonStatic") || IsOfClass(pen, "CannonRotating")) continue; // (guns, not people)
    const FLOAT fDist = (pen->GetPlacement().pl_PositionVector - vPl).Length();
    if (fDist > IOSSELFIE_PHOTOBOMB_RANGE) continue;
    aFound[ctFound].pen = pen;
    aFound[ctFound].fDist = fDist;
    ctFound++;
  }
  // nearest first (a few hundred at most: a simple sort)
  for (int i = 1; i < ctFound; i++) {
    Found f = aFound[i];
    int j = i;
    for (; j > 0 && aFound[j - 1].fDist > f.fDist; j--) aFound[j] = aFound[j - 1];
    aFound[j] = f;
  }
  // (all of them can stand in front of a face)
  _ctBlockers = 0;
  for (int i = 0; i < ctFound && _ctBlockers < IOSSELFIE_MAX_BLOCKERS; i++) {
    IOSSelfieBlocker &b = _aBlockers[_ctBlockers++];
    FLOAT fHeight;
    b.pen = aFound[i].pen;
    IOSSelfie_Measure(b.pen, b.vHead, b.vMid, fHeight, b.fHeadR, b.fBodyR);
  }
  int bBomber = IOSStance_Chance(IOSSELFIE_PHOTOBOMB_CHANCE);
  for (int i = 0; i < ctFound && _ctPeople < IOSSELFIE_MAX_PERSONS; i++) {
    CEntity *pen = aFound[i].pen;
    const int bNear = aFound[i].fDist <= IOSSELFIE_RANGE && _ctPeople <= _ctMaxPeople;
    if (!bNear && !bBomber) continue;
    IOSSelfiePerson &p = _aPeople[_ctPeople];
    p.pen = pen;
    p.bPlayer = 0;
    p.fDist = aFound[i].fDist;
    IOSSelfie_Measure(pen, p.vHead, p.vMid, p.fHeight, p.fHeadR, p.fBodyR);
    // in the player's sight
    if (!IOSPhotoCam_Clear(vEye, p.vHead, p.fHeadR) && !IOSPhotoCam_Clear(vEye, p.vMid, p.fBodyR)) {
      p.pen = NULL;
      continue;
    }
    p.bPhotobomb = !bNear;
    if (!bNear) bBomber = 0; // (one)
    _ctPeople++;
  }
}

// Remembers everyone as they are, to put back exactly
static void IOSSelfie_Save(void)
{
  for (int i = 0; i < _ctPeople; i++) {
    IOSSelfiePerson &p = _aPeople[i];
    p.pl = p.pen->en_plPlacement;
    p.mRot = p.pen->en_mRotation;
    IOSStance_Save(p.pen->GetModelObject(), p.anim);
    if (p.bPlayer) {
      CPlayer *pl = (CPlayer *)&*p.pen;
      p.plView = pl->en_plViewpoint;
      p.plLastView = pl->en_plLastViewpoint;
      CAttachmentModelObject *pamo = pl->GetModelObject()->GetAttachmentModel(0);
      if (pamo != NULL) IOSStance_Save(&pamo->amo_moModelObject, p.animBody);
    }
  }
}

static void IOSSelfie_PutBack(void)
{
  for (int i = 0; i < _ctPeople; i++) {
    IOSSelfiePerson &p = _aPeople[i];
    if (p.pen == NULL || (p.pen->GetFlags() & ENF_DELETED)) continue;
    p.pen->en_plPlacement = p.pl;
    p.pen->en_mRotation = p.mRot;
    IOSStance_Restore(p.pen->GetModelObject(), p.anim);
    if (p.bPlayer) {
      CPlayer *pl = (CPlayer *)&*p.pen;
      pl->en_plViewpoint = p.plView;
      pl->en_plLastViewpoint = p.plLastView;
      CAttachmentModelObject *pamo = pl->GetModelObject()->GetAttachmentModel(0);
      if (pamo != NULL) IOSStance_Restore(&pamo->amo_moModelObject, p.animBody);
    }
  }
}

// As the first frame of the selfie is drawn: the people, the camera, the poses
static int IOSSelfie_Prepare(int iW, int iH)
{
  (void)iW;
  (void)iH;
  CPlayer *pl = (CPlayer *)IOSPhotoCam_Player();
  if (pl == NULL) {
    _bFailed = 1;
    return 0;
  }
  IOSStance_Seed((unsigned int)(_pTimer->GetHighPrecisionTimer().GetSeconds() * 1000.0) * 2654435761u);
  IOSPhotoCam_SetFov(IOSSELFIE_FOV);
  IOSPhotoCam_SetFlash(1); // (a phone's flash: the faces lit, however the level is lit behind them)
  _bPhoneLeft = IOSStance_Rand(10) < 4;
  const int r = IOSStance_Rand(100);
  _fLift = (r < 20) ? IOSSELFIE_LIFT_UP : ((r < 35) ? IOSSELFIE_LIFT_DOWN : IOSSELFIE_LIFT);
  IOSSelfie_FindPeople(pl);
  // the photobomber is only in it if they would be in the photo: placed
  // without them, then checked
  int iBomber = -1;
  for (int i = 1; i < _ctPeople; i++) {
    if (_aPeople[i].bPhotobomb) iBomber = i;
  }
  IOSSelfiePerson bomber;
  if (iBomber >= 0) {
    bomber = _aPeople[iBomber];
    for (int i = iBomber; i < _ctPeople - 1; i++) _aPeople[i] = _aPeople[i + 1];
    _aPeople[--_ctPeople].pen = NULL;
  }
  if (!IOSSelfie_PlaceCamera()) {
    _bFailed = 1;
    return 0;
  }
  // the enemies between the camera and the player left out of the photo
  // (posing or not); and those nearer the camera than the player whose
  // heads are out of the frame (only a big piece of them would be in it)
  IOSSelfieView v;
  IOSSelfie_MakeView(v, _vCam, IOSSelfie_AimPoint(), 0.0f);
  const FLOAT fPlayer = (_aPeople[0].vMid - _vCam).Length();
  for (int j = 0; j < _ctBlockers; j++) {
    const IOSSelfieBlocker &b = _aBlockers[j];
    FLOAT x, y, z;
    IOSSelfie_Project(v, b.vHead, x, y, z);
    const int bHeadOut = z <= 0.05f || fabs(x) > 1.0f || fabs(y) > 1.0f;
    if (IOSSelfie_InFront(_vCam, b.vMid, b.fBodyR) || (bHeadOut && (b.vMid - _vCam).Length() < fPlayer)) {
      IOSPhotoCam_Hide(b.pen);
    }
  }
  for (int i = 0; i < _ctPeople; i++) {
    _aPeople[i].bInFrame = i == 0 || (IOSSelfie_InFrame(v, _aPeople[i]) && _aPeople[i].fDist <= IOSSELFIE_RANGE
                                      && !IOSPhotoCam_IsHidden(_aPeople[i].pen));
  }
  if (iBomber >= 0) {
    _aPeople[_ctPeople] = bomber;
    if (IOSSelfie_InFrame(v, bomber) && !IOSPhotoCam_IsHidden(bomber.pen) && IOSSelfie_FaceClear(_vCam, _ctPeople)) {
      _aPeople[_ctPeople].bInFrame = 1;
      _ctPeople++;
    }
    else {
      _aPeople[_ctPeople].pen = NULL;
    }
  }
  IOSSelfie_Save();
  IOSSelfie_Pose();
  _bPosed = 1;
  return 1;
}

extern "C" int IOSSelfie_Begin(void)
{
  if (_bActive || IOSPhotoCam_IsActive()) return 0;
  _bPosed = _bFailed = 0;
  _ctPeople = 0;
  if (!IOSPhotoCam_Begin(IOSSelfie_Prepare)) return 0;
  _bActive = 1;
  return 1;
}

extern "C" int IOSSelfie_IsActive(void)
{
  return _bActive;
}

extern "C" int IOSSelfie_IsPosed(void)
{
  return _bActive && _bPosed;
}

extern "C" int IOSSelfie_Failed(void)
{
  return _bActive && _bFailed;
}

extern "C" void IOSSelfie_Repose(void)
{
  if (!_bActive || !_bPosed) return;
  IOSSelfie_Pose();
}

extern "C" void IOSSelfie_End(void)
{
  if (!_bActive) return;
  if (_bPosed) IOSSelfie_PutBack();
  for (int i = 0; i < IOSSELFIE_MAX_PERSONS; i++) _aPeople[i].pen = NULL;
  _ctPeople = 0;
  _bPosed = _bFailed = 0;
  _bActive = 0;
  IOSPhotoCam_End();
}

extern "C" void IOSSelfie_SetMaxPeople(int ct)
{
  _ctMaxPeople = Clamp(ct, 0, IOSSELFIE_MAX_PEOPLE_LIMIT);
}

extern "C" int IOSSelfie_NumPosed(void)
{
  int ct = 0;
  for (int i = 1; i < _ctPeople; i++) ct += _aPeople[i].bInFrame;
  return ct;
}
