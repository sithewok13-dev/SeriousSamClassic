// The touch controls' CAMERA: a selfie (as the Jedi Knight port's iosSelfie,
// rebuilt for the Serious Engine). The game holds still; the view switches
// to a camera held out at the player and the enemies nearest them: up to
// IOSSELFIE_MAX_PEOPLE of them (Sam has far more about than Jedi Knight's 8)
// turn to it and strike a pose, each a frame of one of its own animations
// (the classic enemies have no bones). The camera stays at arm's length or
// a little more (further only where there is no room near), keeping the
// nearest faces clear, and never looks down steeply; the player turns to it
// too, an arm up or showing off the gun. Everyone else stays as they were,
// frozen mid-attack. Shots and blasts in front of a face are left out of
// the photo, and so is any enemy nearer the camera than the player (the
// player is the nearest in it, and so is any level with them and over
// them); in a tight crowd, people pose calmly. A flash lights the faces
// near the camera, however the level is lit behind them. Every pose is put back exactly as it was when it ends, so a
// selfie changes nothing in the game. Built on IOSPhotoCam; IOSSelfieShots
// takes the photos. In the game library, on the game's thread.

#ifndef IOSSELFIE_H
#define IOSSELFIE_H

#ifdef __cplusplus
extern "C" {
#endif

// Who can pose in one selfie besides the player (at most; it can be set as
// low as 0 or as high as IOSSELFIE_MAX_PEOPLE_LIMIT)
#define IOSSELFIE_MAX_PEOPLE 48
#define IOSSELFIE_MAX_PEOPLE_LIMIT 64

// Starts it: 0 where there is no selfie to be had (the player dead, a
// cutscene, the sniper scope...). The people and the camera are found, and
// everyone posed, as the first frame of it is drawn (after the game's ticks
// for that frame): then IOSSelfie_IsPosed, or IOSSelfie_Failed where there
// turned out to be no room for the camera.
int IOSSelfie_Begin(void);
int IOSSelfie_IsActive(void);
int IOSSelfie_IsPosed(void);
int IOSSelfie_Failed(void);
// Everyone posed afresh (the next photo), drawn so in the next frame
void IOSSelfie_Repose(void);
// Everything put back as it was, and the view back to the player's
void IOSSelfie_End(void);
// How many may pose (IOSSELFIE_MAX_PEOPLE unless set), and how many are
// posed in it now
void IOSSelfie_SetMaxPeople(int ct);
int IOSSelfie_NumPosed(void);

#ifdef __cplusplus
}
#endif

#endif // IOSSELFIE_H
