// The touch controls' CAMERA: the photo view. See IOSPhotoCam.h.

#include <GameMP/StdAfx.h>
// (more of the game's entities than StdAfx.h has, as it includes them)
#ifdef _MSC_VER
#define DECL_DLL _declspec(dllimport)
#else
#define DECL_DLL
#endif
#ifdef FIRST_ENCOUNTER
#include <Entities/PlayerWeapons.h>
#else
#include <EntitiesMP/PlayerWeapons.h>
#endif
#undef DECL_DLL
#include <GameMP/Camera.h>
#include "IOSPhotoCam.h"
#include "IOSCapture.h"

// The player's view's field of view's fix for wide screens (as Player.es has it)
#ifdef PLATFORM_UNIX
extern "C" __attribute__ ((visibility("default"))) FLOAT _fPlayerFOVAdjuster;
#else
extern __declspec(dllimport) FLOAT _fPlayerFOVAdjuster;
#endif

#define IOSPHOTOCAM_MAX_HIDDEN 256
// The models a camera mustn't be inside (enemies, trees, statues...):
// those within IOSPHOTOCAM_SOLID_RANGE of the player as the first frame is
// drawn, at most IOSPHOTOCAM_MAX_SOLIDS of them, each as its box shrunk to
// IOSPHOTOCAM_SOLID_SHRINK round its middle
#define IOSPHOTOCAM_MAX_SOLIDS 512
#define IOSPHOTOCAM_SOLID_RANGE 60.0f
#define IOSPHOTOCAM_SOLID_SHRINK 0.7f

static int _bActive = 0;
static int _bPrepared = 0, _bPrepareFailed = 0;
static int (*_pfnPrepare)(int iW, int iH) = NULL;
static FLOAT3D _vCamPos(0, 0, 0);
static ANGLE3D _aCamRot(0, 0, 0);
static FLOAT _fFov = IOSPHOTOCAM_FOV_DEFAULT;
static FLOAT _fAspect = 16.0f / 9.0f;
static CEntityPointer _penPlayer;
static FLOAT3D _vEye(0, 0, 0);
static ANGLE3D _aView(0, 0, 0);
static int _bHidePlayer = 0;
// Hidden from the view: each entity and how it was drawn
static CEntityPointer _apenHidden[IOSPHOTOCAM_MAX_HIDDEN];
static enum CEntity::RenderType _aeHiddenRender[IOSPHOTOCAM_MAX_HIDDEN];
static ULONG _aulHiddenFlags[IOSPHOTOCAM_MAX_HIDDEN];
static int _ctHidden = 0;
// The level near the player (its brushes' sectors and its terrains), for the
// lines through it: a line within IOSPHOTOCAM_LEVEL_RANGE of the player is
// tested against the sectors its box touches only (else against the whole
// level, as the game's own lines are: much slower)
#define IOSPHOTOCAM_MAX_SECTORS 8192
#define IOSPHOTOCAM_MAX_TERRAINS 16
#define IOSPHOTOCAM_LEVEL_RANGE 150.0f
static CBrushSector *_apbscSectors[IOSPHOTOCAM_MAX_SECTORS];
static int _ctSectors = 0;
static CEntity *_apenTerrains[IOSPHOTOCAM_MAX_TERRAINS];
static int _ctTerrains = 0;
static int _bLevelKnown = 0;
static FLOATaabbox3D _boxLevel;
static FLOATaabbox3D _aboxSolids[IOSPHOTOCAM_MAX_SOLIDS];
static CEntity *_apenSolids[IOSPHOTOCAM_MAX_SOLIDS];
static int _ctSolids = 0;

// The models near the player, as boxes (not the player's own, nor shots,
// blasts, items or anything too small to be in the way)
static void IOSPhotoCam_FindSolids(void)
{
  _ctSolids = 0;
  FOREACHINDYNAMICCONTAINER(_pNetwork->ga_World.wo_cenEntities, CEntity, iten) {
    CEntity *pen = &*iten;
    if (_ctSolids >= IOSPHOTOCAM_MAX_SOLIDS) break;
    if (pen == (CEntity *)_penPlayer || pen->GetRenderType() != CEntity::RT_MODEL || pen->GetModelObject() == NULL) continue;
    if (IsOfClass(pen, "Projectile") || IsOfClass(pen, "BasicEffect") || IsOfClass(pen, "Debris")
        || IsDerivedFromClass(pen, "Item")) continue;
    if (IsDerivedFromClass(pen, "Enemy Base") && !(pen->GetFlags() & ENF_ALIVE)) continue;
    FLOATaabbox3D box;
    pen->GetBoundingBox(box);
    if (box.Size().Length() < 0.5f || (box.Center() - _vEye).Length() > IOSPHOTOCAM_SOLID_RANGE) continue;
    // (a model's box holds its limbs, horns, wings at their widest: the body
    // is well inside it)
    const FLOAT3D c = box.Center(), h = box.Size() * (0.5f * IOSPHOTOCAM_SOLID_SHRINK);
    _apenSolids[_ctSolids] = pen;
    _aboxSolids[_ctSolids++] = FLOATaabbox3D(c - h, c + h);
  }
}

// The level near the player, as the game's whole-level lines see it (the
// same brush mips, no hidden sectors, no field brushes)
static void IOSPhotoCam_FindLevel(void)
{
  _ctSectors = _ctTerrains = 0;
  _bLevelKnown = 0;
  _boxLevel = FLOATaabbox3D(_vEye, IOSPHOTOCAM_LEVEL_RANGE);
  FOREACHINDYNAMICCONTAINER(_pNetwork->ga_World.wo_cenEntities, CEntity, iten) {
    CEntity *pen = &*iten;
    if (pen->en_ulFlags & ENF_HIDDEN) continue;
    if (pen->en_RenderType == CEntity::RT_TERRAIN) {
      if (_ctTerrains >= IOSPHOTOCAM_MAX_TERRAINS) return; // (too much: the whole level for every line)
      _apenTerrains[_ctTerrains++] = pen;
      continue;
    }
    if (pen->en_RenderType != CEntity::RT_BRUSH || pen->en_pbrBrush == NULL) continue;
    CBrushMip *pbm = pen->en_pbrBrush->GetBrushMipByDistance(_wrpWorldRenderPrefs.GetManualMipBrushingFactor());
    if (pbm == NULL) continue;
    FOREACHINDYNAMICARRAY(pbm->bm_abscSectors, CBrushSector, itbsc) {
      if ((itbsc->bsc_ulFlags & BSCF_HIDDEN) || !itbsc->bsc_boxBoundingBox.HasContactWith(_boxLevel)) continue;
      if (_ctSectors >= IOSPHOTOCAM_MAX_SECTORS) return;
      _apbscSectors[_ctSectors++] = &*itbsc;
    }
  }
  _bLevelKnown = 1;
}

int IOSPhotoCam_InModel(const FLOAT3D &v, FLOAT fR)
{
  for (int i = 0; i < _ctSolids; i++) {
    const FLOATaabbox3D &b = _aboxSolids[i];
    if (v(1) > b.minvect(1) - fR && v(1) < b.maxvect(1) + fR && v(2) > b.minvect(2) - fR && v(2) < b.maxvect(2) + fR
        && v(3) > b.minvect(3) - fR && v(3) < b.maxvect(3) + fR) return 1;
  }
  return 0;
}

extern "C" int IOSPhotoCam_IsActive(void)
{
  return _bActive;
}

// The local player of a single-player game, alive (NULL if not)
static CPlayer *IOSPhotoCam_FindPlayer(void)
{
  FOREACHINDYNAMICCONTAINER(_pNetwork->ga_World.wo_cenEntities, CEntity, iten) {
    CEntity *pen = &*iten;
    if (!IsOfClass(pen, "Player") || pen->IsPredictor()) continue;
    return (CPlayer *)pen;
  }
  return NULL;
}

// Where the player looks from (the world doesn't move now; read again as
// the first frame is drawn, after the ticks waiting for it)
static void IOSPhotoCam_ReadEye(void)
{
  CPlayer *pl = (CPlayer *)&*_penPlayer;
  if (pl == NULL) return;
  CPlacement3D plEye = pl->en_plViewpoint;
  plEye.RelativeToAbsolute(pl->GetPlacement());
  _vEye = plEye.pl_PositionVector;
  _aView = plEye.pl_OrientationAngle;
}

int IOSPhotoCam_Begin(int (*pfnPrepare)(int iW, int iH))
{
  if (_bActive) return 0;
  // (single player only: the world can't be held still for one player in a
  // game with others, nor while the debug camera has the view)
  if (!GetSP()->sp_bSinglePlayer || CAM_IsOn()) return 0;
  CPlayer *pl = IOSPhotoCam_FindPlayer();
  if (pl == NULL || !(pl->GetFlags() & ENF_ALIVE)) return 0;
  if (pl->m_penCamera != NULL) return 0; // a cutscene
#ifndef FIRST_ENCOUNTER
  if (pl->m_penWeapons != NULL && ((CPlayerWeapons &)*pl->m_penWeapons).m_bSniping) return 0; // the scope
#endif
  _penPlayer = pl;
  IOSPhotoCam_ReadEye();
  _vCamPos = _vEye;
  _aCamRot = _aView;
  _fFov = IOSPHOTOCAM_FOV_DEFAULT;
  _pfnPrepare = pfnPrepare;
  _bPrepared = _bPrepareFailed = 0;
  _ctHidden = 0;
  _ctSolids = 0;
  _bLevelKnown = 0;
  _bHidePlayer = 0;
  _bActive = 1;
  return 1;
}

void IOSPhotoCam_End(void)
{
  if (!_bActive) return;
  for (int i = 0; i < _ctHidden; i++) {
    CEntity *pen = _apenHidden[i];
    if (pen != NULL && !(pen->GetFlags() & ENF_DELETED)) {
      pen->en_RenderType = _aeHiddenRender[i];
      pen->en_ulFlags = (pen->en_ulFlags & ~ENF_HASPARTICLES) | (_aulHiddenFlags[i] & ENF_HASPARTICLES);
    }
    _apenHidden[i] = NULL;
  }
  _ctHidden = 0;
  _ctSolids = 0;
  _penPlayer = NULL;
  _pfnPrepare = NULL;
  _bActive = 0;
}

int IOSPhotoCam_IsPrepared(void)
{
  return _bActive && _bPrepared;
}

int IOSPhotoCam_PrepareFailed(void)
{
  return _bPrepareFailed;
}

void IOSPhotoCam_Place(const FLOAT3D &vPos, const ANGLE3D &aRot)
{
  _vCamPos = vPos;
  _aCamRot = aRot;
}

void IOSPhotoCam_GetPlace(FLOAT3D &vPos, ANGLE3D &aRot)
{
  vPos = _vCamPos;
  aRot = _aCamRot;
}

void IOSPhotoCam_SetFov(FLOAT fVertical)
{
  _fFov = Clamp(fVertical, IOSPHOTOCAM_FOV_MIN, IOSPHOTOCAM_FOV_MAX);
}

FLOAT IOSPhotoCam_GetFov(void)
{
  return _fFov;
}

FLOAT IOSPhotoCam_Aspect(void)
{
  return _fAspect;
}

FLOAT IOSPhotoCam_GameFov(void)
{
  // (as the player's view has it: across the whole width, with its fix for
  // wide screens; the same in every game mode a photo view is had in)
  FLOAT fAcross = _pShell->GetFLOAT("plr_fFOV");
  if (_pShell->GetINDEX("plr_bEnablePlayerFOVFix") && _fPlayerFOVAdjuster > 0.1f) fAcross *= _fPlayerFOVAdjuster;
  fAcross = Clamp(fAcross, 10.0f, 170.0f);
  const FLOAT fHalf = fAcross * 0.5f * PI / 180.0f;
  return 2.0f * atan(tan(fHalf) / Max(_fAspect, 0.1f)) * 180.0f / PI;
}

CEntity *IOSPhotoCam_Player(void)
{
  return _penPlayer;
}

void IOSPhotoCam_PlayerView(FLOAT3D &vEye, ANGLE3D &aView)
{
  vEye = _vEye;
  aView = _aView;
}

FLOAT IOSPhotoCam_ClearDist(const FLOAT3D &vFrom, const FLOAT3D &vTo)
{
  const FLOAT fLen = (vTo - vFrom).Length();
  if (fLen < 0.001f) return fLen;
  CCastRay cr(NULL, vFrom, vTo);
  cr.cr_ttHitModels = CCastRay::TT_NONE;   // the level only (brushes, terrain)
  cr.cr_bHitTranslucentPortals = FALSE;    // (bars, glass, force fields are seen through)
  cr.cr_bPhysical = FALSE;
  FLOATaabbox3D boxRay(vFrom);
  boxRay |= FLOATaabbox3D(vTo);
  if (_bLevelKnown && _boxLevel >= boxRay) {
    // (as the game's whole-level line does, but only where the line goes)
    cr.cr_pbpoBrushPolygon = NULL;
    cr.cr_pbscBrushSector = NULL;
    cr.cr_penHit = NULL;
    cr.cr_ulPassablePolygons = BPOF_PORTAL | BPOF_OCCLUDER;
    for (int i = 0; i < _ctSectors; i++) {
      if (_apbscSectors[i]->bsc_boxBoundingBox.HasContactWith(boxRay)) cr.TestBrushSector(_apbscSectors[i]);
    }
    for (int i = 0; i < _ctTerrains; i++) cr.TestTerrain(_apenTerrains[i]);
  }
  else {
    _pNetwork->ga_World.CastRay(cr);
  }
  if (cr.cr_penHit == NULL) return fLen;
  return Min(cr.cr_fHitDistance, fLen);
}

int IOSPhotoCam_Clear(const FLOAT3D &vFrom, const FLOAT3D &vTo, FLOAT fSlack)
{
  return IOSPhotoCam_ClearDist(vFrom, vTo) >= (vTo - vFrom).Length() - fSlack;
}

int IOSPhotoCam_RoomAt(const FLOAT3D &vFrom, const FLOAT3D &v, FLOAT fR)
{
  if (IOSPhotoCam_InModel(v, fR)) return 0;
  if (!IOSPhotoCam_Clear(vFrom, v, 0.0f)) return 0;
  static const FLOAT3D avDir[6] = { FLOAT3D(1, 0, 0), FLOAT3D(-1, 0, 0), FLOAT3D(0, 1, 0),
                                    FLOAT3D(0, -1, 0), FLOAT3D(0, 0, 1), FLOAT3D(0, 0, -1) };
  for (int i = 0; i < 6; i++) {
    if (!IOSPhotoCam_Clear(v, v + avDir[i] * fR, 0.0f)) return 0;
  }
  return 1;
}

void IOSPhotoCam_Hide(CEntity *pen)
{
  if (!_bActive || pen == NULL || IOSPhotoCam_IsHidden(pen) || _ctHidden >= IOSPHOTOCAM_MAX_HIDDEN) return;
  _apenHidden[_ctHidden] = pen;
  _aeHiddenRender[_ctHidden] = pen->en_RenderType;
  _aulHiddenFlags[_ctHidden] = pen->en_ulFlags;
  _ctHidden++;
  pen->en_RenderType = CEntity::RT_NONE;
  pen->en_ulFlags &= ~ENF_HASPARTICLES;
}

void IOSPhotoCam_SetHidePlayer(int bHide)
{
  _bHidePlayer = bHide != 0;
}

int IOSPhotoCam_IsHidden(CEntity *pen)
{
  for (int i = 0; i < _ctHidden; i++) {
    if (_apenHidden[i] == pen) return 1;
  }
  return 0;
}

int IOSPhotoCam_Render(CEntity *penViewer, CDrawPort *pdp)
{
  if (!_bActive || penViewer == NULL || pdp == NULL) return 0;
  const FLOAT fW = (FLOAT)pdp->GetWidth(), fH = (FLOAT)pdp->GetHeight();
  if (fW < 1.0f || fH < 1.0f) return 0;
  _fAspect = fW / fH;
  if (!_bPrepared) {
    _bPrepared = 1;
#ifdef IOS_CAMERA_RIG_DEBUG
    const CTimerValue tv0 = _pTimer->GetHighPrecisionTimer();
#endif
    IOSPhotoCam_ReadEye();
    IOSPhotoCam_FindLevel();
    IOSPhotoCam_FindSolids();
    if (_pfnPrepare != NULL && !_pfnPrepare((int)fW, (int)fH)) _bPrepareFailed = 1;
#ifdef IOS_CAMERA_RIG_DEBUG
    printf("RIGDBG prepare %.1f ms\n", (_pTimer->GetHighPrecisionTimer() - tv0).GetSeconds() * 1000.0);
#endif
  }
  if (_bPrepareFailed) return 0; // (the game's own view, until it ends)

  // The game's horizontal field of view from the vertical one
  const FLOAT fHalfV = _fFov * 0.5f * PI / 180.0f;
  const FLOAT aFovH = 2.0f * atan(tan(fHalfV) * _fAspect) * 180.0f / PI;
  CPerspectiveProjection3D pr;
  pr.FOVL() = aFovH;
  pr.ScreenBBoxL() = FLOATaabbox2D(FLOAT2D(0.0f, 0.0f), FLOAT2D(fW, fH));
  pr.AspectRatioL() = 1.0f;
  pr.FrontClipDistanceL() = Clamp(_pShell->GetFLOAT("plr_fFrontClipDistance"), 0.05f, 0.5f); // (as the game's own view)
  CAnyProjection3D apr;
  apr = pr;
  apr->ViewerPlacementL() = CPlacement3D(_vCamPos, _aCamRot);

  // Nothing moves: drawn exactly where everything is (no lerping between ticks)
  const FLOAT fLerp = _pTimer->GetLerpFactor(), fLerp2 = _pTimer->GetLerpFactor2();
  _pTimer->SetLerp(1.0f);
  // (no viewer entity: the player is drawn as anyone else, and what is seen
  // is found round the camera)
  // (the player's own body left out while the camera is in or by their head)
  CEntity *penPlayer = _penPlayer;
  const enum CEntity::RenderType rtPlayer = (penPlayer != NULL) ? penPlayer->en_RenderType : CEntity::RT_NONE;
  if (_bHidePlayer && penPlayer != NULL) penPlayer->en_RenderType = CEntity::RT_NONE;
  RenderView(*penViewer->en_pwoWorld, *(CEntity *)NULL, apr, *pdp);
  if (_bHidePlayer && penPlayer != NULL) penPlayer->en_RenderType = rtPlayer;
  _pTimer->SetLerp(fLerp);
  _pTimer->SetLerp2(fLerp2);
  // (CAMERA's photo of this view: before the console's lines or anything
  // else the game draws over it)
  IOSCapture_AfterScene();
  return 1;
}
