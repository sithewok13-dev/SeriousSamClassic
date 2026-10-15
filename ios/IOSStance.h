// The touch controls' CAMERA: poses for a selfie. The game's enemies (and the
// player) are models without bones, so a pose is one frame of one of the
// model's own animations, chosen by the animation's name: an attack (mid
// swing, mid shot), a roar, standing about, a flinch, or mid-stride. The
// frame is held (the animation paused on it) until it is put back exactly
// as it was. Also the selfie's own random numbers, apart from the game's.
// In the game library, on the game's thread.

#ifndef IOSSTANCE_H
#define IOSSTANCE_H

#ifdef __cplusplus

// Kinds of pose
enum {
  IOSSTANCE_ATTACK = 0, // mid attack: a swing, a shot, a bite, a kick...
  IOSSTANCE_ANGER,      // a roar, a taunt
  IOSSTANCE_IDLE,       // standing about
  IOSSTANCE_WOUND,      // a flinch
  IOSSTANCE_MOVE,       // mid-stride, mid-leap
  IOSSTANCE_NUM
};

// The player's poses
enum {
  IOSSTANCE_PLAYER_PHONE = 0, // an arm up, as if holding the phone up
  IOSSTANCE_PLAYER_GUN,       // showing off the gun (its stance or a shot)
  IOSSTANCE_PLAYER_PULL,      // both arms out
  IOSSTANCE_PLAYER_LOOK,      // looking about
  IOSSTANCE_PLAYER_NUM
};

class CModelObject;

// The selfie's own random numbers (the game's stay as they were): seeds
// them, a number 0..n-1, a float 0..1, true one time in n
void IOSStance_Seed(unsigned int uSeed);
int IOSStance_Rand(int n);
FLOAT IOSStance_Rand01(void);
int IOSStance_Chance(int n);

// A kind of pose at random (attacks most, flinches least)
int IOSStance_RandomKind(void);

// An animation and frame of this model for a pose of this kind (or the
// nearest kind it has): 0 if it has none fit for a pose
int IOSStance_Pick(CModelObject *pmo, int iKind, INDEX &iAnim, INDEX &iFrame);
// The animation called exactly this (any case): 0 if there is none
int IOSStance_Find(CModelObject *pmo, const char *strName, INDEX &iAnim);
// The player's: on the body (the player model's torso attachment)
int IOSStance_PickPlayer(CModelObject *pmoBody, int iPose, INDEX &iAnim, INDEX &iFrame);
// A model's animation as it was, to put back exactly
struct IOSStanceSaved {
  INDEX iCurrent, iLast;
  TIME tmStart;
  ULONG ulFlags;
};
void IOSStance_Save(CModelObject *pmo, IOSStanceSaved &s);
void IOSStance_Restore(CModelObject *pmo, const IOSStanceSaved &s);
// Holds the model on that frame of that animation
void IOSStance_Hold(CModelObject *pmo, INDEX iAnim, INDEX iFrame);

#endif // __cplusplus

#endif // IOSSTANCE_H
