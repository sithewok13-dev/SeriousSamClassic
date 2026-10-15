// The touch controls' CAMERA: poses for a selfie. See IOSStance.h.

#include <GameMP/StdAfx.h>
#include <ctype.h>
#include "IOSStance.h"

// ------------------------------------------------------------ random numbers
// (xorshift32: the game's own random numbers aren't touched, so a selfie
// changes nothing of what happens next)

static unsigned int _uRand = 2463534242u;

void IOSStance_Seed(unsigned int uSeed)
{
  _uRand = uSeed ? uSeed : 2463534242u;
}

static unsigned int IOSStance_Next(void)
{
  unsigned int x = _uRand;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  _uRand = x;
  return x;
}

int IOSStance_Rand(int n)
{
  return (n > 1) ? (int)(IOSStance_Next() % (unsigned int)n) : 0;
}

FLOAT IOSStance_Rand01(void)
{
  return (FLOAT)(IOSStance_Next() & 0xFFFFFF) / (FLOAT)0x1000000;
}

int IOSStance_Chance(int n)
{
  return IOSStance_Rand(n) == 0;
}

// ------------------------------------------------------------ the poses

// What an animation's name says it is: words in it, for each kind. An
// animation with any of the last words in its name is never a pose (dying,
// lying dead, being made, falling).
static const char *const _astrKindWords[IOSSTANCE_NUM][16] = {
  { "ATTACK", "FIRE", "SHOOT", "KICK", "PUNCH", "BITE", "SLASH", "CLAW", "MELEE", "SWING", "THROW", "SPIT",
    "STRIKE", "SPELL", "HORN", NULL },
  { "ANGER", "ANGRY", "ROAR", "TAUNT", "SCREAM", "HOWL", "RAGE", "SHOUT", "GROWL", "LAUGH", "CHARGE", NULL },
  { "IDLE", "STAND", "WAIT", "POSE", "LOOK", NULL },
  { "WOUND", "PAIN", "HIT", NULL },
  { "RUN", "WALK", "JUMP", "FLY", "GLIDE", "SWIM", "STEP", NULL },
};
static const char *const _astrNeverWords[] = {
  "DEATH", "DIE", "DEAD", "DEFAULT", "SPAWN", "BIRTH", "FALL", "BURN", "LIE", "CORPSE", "DISAPPEAR", "APPEAR",
  "TRANSFORM", "EXPLODE", NULL
};
// How often each kind is picked (of 10); and which kind a model without
// one of that kind gets instead, in order
static const int _aiKindWeight[IOSSTANCE_NUM] = { 4, 3, 1, 1, 1 };
static const int _aiFallback[IOSSTANCE_NUM][IOSSTANCE_NUM] = {
  { IOSSTANCE_ATTACK, IOSSTANCE_ANGER, IOSSTANCE_IDLE, IOSSTANCE_MOVE, IOSSTANCE_WOUND },
  { IOSSTANCE_ANGER, IOSSTANCE_ATTACK, IOSSTANCE_IDLE, IOSSTANCE_MOVE, IOSSTANCE_WOUND },
  { IOSSTANCE_IDLE, IOSSTANCE_ANGER, IOSSTANCE_ATTACK, IOSSTANCE_MOVE, IOSSTANCE_WOUND },
  { IOSSTANCE_WOUND, IOSSTANCE_ANGER, IOSSTANCE_ATTACK, IOSSTANCE_IDLE, IOSSTANCE_MOVE },
  { IOSSTANCE_MOVE, IOSSTANCE_ATTACK, IOSSTANCE_ANGER, IOSSTANCE_IDLE, IOSSTANCE_WOUND },
};
// Which part of the animation a pose is taken from (fractions of it): an
// attack and a flinch at their height, not as they start or settle
static const FLOAT _afKindFrom[IOSSTANCE_NUM] = { 0.30f, 0.20f, 0.0f, 0.25f, 0.0f };
static const FLOAT _afKindTo[IOSSTANCE_NUM]   = { 0.75f, 0.80f, 1.0f, 0.70f, 1.0f };

static int IOSStance_NameHas(const char *strName, const char *strWord)
{
  char str[64];
  int i = 0;
  for (; strName[i] && i < 63; i++) str[i] = (char)toupper((unsigned char)strName[i]);
  str[i] = 0;
  return strstr(str, strWord) != NULL;
}

static int IOSStance_KindOf(const char *strName)
{
  for (int i = 0; _astrNeverWords[i]; i++) {
    if (IOSStance_NameHas(strName, _astrNeverWords[i])) return -1;
  }
  for (int k = 0; k < IOSSTANCE_NUM; k++) {
    for (int i = 0; _astrKindWords[k][i]; i++) {
      if (IOSStance_NameHas(strName, _astrKindWords[k][i])) return k;
    }
  }
  return -1;
}

int IOSStance_RandomKind(void)
{
  int iTotal = 0;
  for (int k = 0; k < IOSSTANCE_NUM; k++) iTotal += _aiKindWeight[k];
  int r = IOSStance_Rand(iTotal);
  for (int k = 0; k < IOSSTANCE_NUM; k++) {
    if (r < _aiKindWeight[k]) return k;
    r -= _aiKindWeight[k];
  }
  return IOSSTANCE_IDLE;
}

// A frame between those fractions of the animation
static INDEX IOSStance_FrameIn(INDEX ctFrames, FLOAT fFrom, FLOAT fTo)
{
  if (ctFrames <= 1) return 0;
  INDEX i0 = (INDEX)floor(fFrom * (ctFrames - 1) + 0.5f), i1 = (INDEX)floor(fTo * (ctFrames - 1) + 0.5f);
  if (i1 < i0) i1 = i0;
  return i0 + IOSStance_Rand(i1 - i0 + 1);
}

int IOSStance_Pick(CModelObject *pmo, int iKind, INDEX &iAnim, INDEX &iFrame)
{
  if (pmo == NULL || pmo->GetData() == NULL) return 0;
  const INDEX ctAnims = pmo->GetAnimsCt();
  if (ctAnims <= 0) return 0;
  if (iKind < 0 || iKind >= IOSSTANCE_NUM) iKind = IOSSTANCE_IDLE;
  INDEX aiAnims[64];
  for (int f = 0; f < IOSSTANCE_NUM; f++) {
    const int k = _aiFallback[iKind][f];
    int ct = 0;
    for (INDEX i = 0; i < ctAnims && ct < 64; i++) {
      CAnimInfo ai;
      pmo->GetAnimInfo(i, ai);
      if (ai.ai_NumberOfFrames <= 0 || IOSStance_KindOf(ai.ai_AnimName) != k) continue;
      aiAnims[ct++] = i;
    }
    if (ct == 0) continue;
    iAnim = aiAnims[IOSStance_Rand(ct)];
    CAnimInfo ai;
    pmo->GetAnimInfo(iAnim, ai);
    iFrame = IOSStance_FrameIn(ai.ai_NumberOfFrames, _afKindFrom[k], _afKindTo[k]);
    return 1;
  }
  return 0;
}

int IOSStance_Find(CModelObject *pmo, const char *strName, INDEX &iAnim)
{
  if (pmo == NULL || pmo->GetData() == NULL) return 0;
  const INDEX ctAnims = pmo->GetAnimsCt();
  for (INDEX i = 0; i < ctAnims; i++) {
    CAnimInfo ai;
    pmo->GetAnimInfo(i, ai);
    if (ai.ai_NumberOfFrames > 0 && strcasecmp(ai.ai_AnimName, strName) == 0) {
      iAnim = i;
      return 1;
    }
  }
  return 0;
}

// The player's poses: words in the body's animation names (the same for
// every player model), and which part of the animation
static const char *const _astrPlayerWords[IOSSTANCE_PLAYER_NUM] = { "KEYLIFT", "", "STATUE_PULL", "LOOKAROUND" };
static const FLOAT _afPlayerFrom[IOSSTANCE_PLAYER_NUM] = { 0.40f, 0.0f, 0.35f, 0.20f };
static const FLOAT _afPlayerTo[IOSSTANCE_PLAYER_NUM]   = { 0.60f, 1.0f, 0.65f, 0.80f };

int IOSStance_PickPlayer(CModelObject *pmoBody, int iPose, INDEX &iAnim, INDEX &iFrame)
{
  if (pmoBody == NULL || pmoBody->GetData() == NULL || iPose < 0 || iPose >= IOSSTANCE_PLAYER_NUM) return 0;
  const INDEX ctAnims = pmoBody->GetAnimsCt();
  INDEX aiAnims[16];
  int ct = 0;
  if (iPose == IOSSTANCE_PLAYER_GUN) {
    // the weapon in hand's own: its stance or a shot (COLT_STAND,
    // SHOTGUN_FIRELONG...), from the family the body is in now
    CAnimInfo aiNow;
    pmoBody->GetAnimInfo(pmoBody->GetAnim(), aiNow);
    char strFamily[32];
    int n = 0;
    for (; aiNow.ai_AnimName[n] && aiNow.ai_AnimName[n] != '_' && n < 31; n++) strFamily[n] = (char)toupper((unsigned char)aiNow.ai_AnimName[n]);
    strFamily[n] = 0;
    if (!n || (!IOSStance_NameHas(strFamily, "COLT") && !IOSStance_NameHas(strFamily, "SHOTGUN")
               && !IOSStance_NameHas(strFamily, "MINIGUN"))) {
      strcpy(strFamily, "COLT");
    }
    for (INDEX i = 0; i < ctAnims && ct < 16; i++) {
      CAnimInfo ai;
      pmoBody->GetAnimInfo(i, ai);
      if (ai.ai_NumberOfFrames <= 0 || !IOSStance_NameHas(ai.ai_AnimName, strFamily)) continue;
      if (IOSStance_NameHas(ai.ai_AnimName, "SWIM") || IOSStance_NameHas(ai.ai_AnimName, "DRAW")
          || IOSStance_NameHas(ai.ai_AnimName, "DEACTIVATE")) continue;
      aiAnims[ct++] = i;
    }
  }
  else {
    for (INDEX i = 0; i < ctAnims && ct < 16; i++) {
      CAnimInfo ai;
      pmoBody->GetAnimInfo(i, ai);
      if (ai.ai_NumberOfFrames <= 0 || !IOSStance_NameHas(ai.ai_AnimName, _astrPlayerWords[iPose])) continue;
      if (IOSStance_NameHas(ai.ai_AnimName, "ONCE") || IOSStance_NameHas(ai.ai_AnimName, "TO")) continue;
      aiAnims[ct++] = i;
    }
  }
  if (ct == 0) return 0;
  iAnim = aiAnims[IOSStance_Rand(ct)];
  CAnimInfo ai;
  pmoBody->GetAnimInfo(iAnim, ai);
  iFrame = IOSStance_FrameIn(ai.ai_NumberOfFrames, _afPlayerFrom[iPose], _afPlayerTo[iPose]);
  return 1;
}

void IOSStance_Save(CModelObject *pmo, IOSStanceSaved &s)
{
  s.iCurrent = pmo->ao_iCurrentAnim;
  s.iLast = pmo->ao_iLastAnim;
  s.tmStart = pmo->ao_tmAnimStart;
  s.ulFlags = pmo->ao_ulFlags;
}

void IOSStance_Restore(CModelObject *pmo, const IOSStanceSaved &s)
{
  pmo->ao_iCurrentAnim = s.iCurrent;
  pmo->ao_iLastAnim = s.iLast;
  pmo->ao_tmAnimStart = s.tmStart;
  pmo->ao_ulFlags = s.ulFlags;
  pmo->MarkChanged();
}

void IOSStance_Hold(CModelObject *pmo, INDEX iAnim, INDEX iFrame)
{
  CAnimInfo ai;
  pmo->GetAnimInfo(iAnim, ai);
  pmo->ao_iCurrentAnim = iAnim;
  pmo->ao_iLastAnim = iAnim;
  pmo->ao_ulFlags = AOF_PAUSED | AOF_LOOPING;
  // (paused, the start time is how far into it: a little into the frame, so
  // it lands on it whether that is rounded down or to the nearest)
  pmo->ao_tmAnimStart = (iFrame + 0.25f) * ai.ai_SecsPerFrame;
  pmo->MarkChanged();
}
