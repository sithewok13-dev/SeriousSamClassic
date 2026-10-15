// The touch controls' CAMERA: a view of the game from a camera of its own
// (as the Jedi Knight port's iosPhotoCam). While it is on, the game holds
// still (the overlay sees to that: IOSTouch_HoldsGame), and the game's view
// is drawn from this camera instead of the player's eyes: no HUD, no
// first-person weapon, the player's own body seen as anyone else's. Selfies
// (IOSSelfie), Action Freeze (IOSFreeze) and the cinematic burst
// (IOSCinema) are built on it. Nothing in the level is changed by it, apart
// from what those put back themselves; entities it hides from the view are
// shown again when it ends. In the game library (it works on the game's
// entities), on the game's thread.

#ifndef IOSPHOTOCAM_H
#define IOSPHOTOCAM_H

#ifdef __cplusplus
extern "C" {
#endif

// Whether the photo view is on
int IOSPhotoCam_IsActive(void);

#ifdef __cplusplus
}

// The vertical field of view a photo view starts with, and its limits
#define IOSPHOTOCAM_FOV_DEFAULT 70.0f
#define IOSPHOTOCAM_FOV_MIN 15.0f
#define IOSPHOTOCAM_FOV_MAX 110.0f

class CEntity;
class CDrawPort;

// Takes over the view, from where the player is looking. 0 where there is no
// photo view to be had: not a single-player game being played, the player
// dead, a cutscene's camera, the sniper scope. pfnPrepare (may be NULL) is
// called once, as the first frame of the view is drawn, with that frame's
// size in pixels: the game's ticks waiting for this frame have run by then,
// so what it sets up can't be seen by one. It returns 0 if the view can't
// go on (it then ends).
int IOSPhotoCam_Begin(int (*pfnPrepare)(int iW, int iH));
// Ends it: everything it hid shows again, and the player's view is back
void IOSPhotoCam_End(void);
// Whether its first frame was drawn (and set up), and whether that failed
int IOSPhotoCam_IsPrepared(void);
int IOSPhotoCam_PrepareFailed(void);

// The camera: where it is and its heading, pitch and banking (degrees, as
// the game's); its vertical field of view (degrees, clamped)
void IOSPhotoCam_Place(const FLOAT3D &vPos, const ANGLE3D &aRot);
void IOSPhotoCam_GetPlace(FLOAT3D &vPos, ANGLE3D &aRot);
void IOSPhotoCam_SetFov(FLOAT fVertical);
FLOAT IOSPhotoCam_GetFov(void);
// The width of the view over its height (from the last frame drawn); the
// game's own view's vertical field of view
FLOAT IOSPhotoCam_Aspect(void);
FLOAT IOSPhotoCam_GameFov(void);

// The player, where their eyes are and which way they look (as the game
// last drew it), and whether they were seen from their eyes
CEntity *IOSPhotoCam_Player(void);
void IOSPhotoCam_PlayerView(FLOAT3D &vEye, ANGLE3D &aView);

// Lines through the level: how far from vFrom towards vTo before a wall, a
// closed door or a lift (not models); the whole way if nothing is in it
FLOAT IOSPhotoCam_ClearDist(const FLOAT3D &vFrom, const FLOAT3D &vTo);
// Whether nothing of the level is between the two (within fSlack of vTo
// counts as clear)
int IOSPhotoCam_Clear(const FLOAT3D &vFrom, const FLOAT3D &vTo, FLOAT fSlack);
// Whether a ball of radius fR at v is clear of the level (a camera there
// shows no wall's inside or edge), seen from vFrom (in the clear), and out of
// every model near the player (enemies, trees, statues: by their boxes)
int IOSPhotoCam_RoomAt(const FLOAT3D &vFrom, const FLOAT3D &v, FLOAT fR);
// (just the models)
int IOSPhotoCam_InModel(const FLOAT3D &v, FLOAT fR);

// Hides this entity (and its particles) from the photo view, until it ends
void IOSPhotoCam_Hide(CEntity *pen);
int IOSPhotoCam_IsHidden(CEntity *pen);
// Leaves the player's own body out of the view (only while it is drawn)
void IOSPhotoCam_SetHidePlayer(int bHide);

// (Game.cpp) Draws the photo view for this viewer into pdp, locked: 1 if it
// did (the game draws nothing else of the view then: no HUD, no messages)
int IOSPhotoCam_Render(CEntity *penViewer, CDrawPort *pdp);

#endif // __cplusplus

#endif // IOSPHOTOCAM_H
