// Action Freeze (as the Jedi Knight port's iosFreeze): the game stops where
// it is and a camera turns round what the player was looking at. One finger
// turns it round, two move it and pinch to zoom; it keeps out of walls and
// closed doors, moving in where it has to and gliding back out once there is
// room. Nothing in the level is changed: the game simply doesn't run. Built
// on IOSPhotoCam. Called on the game's thread (the overlay's touches, once a
// frame before it is drawn).

#ifndef IOSFREEZE_H
#define IOSFREEZE_H

#ifdef __cplusplus
extern "C" {
#endif

// Stops the game and takes over the view: 0 if it can't here (a cutscene,
// the sniper scope, the player dead), and then nothing has changed.
int IOSFreeze_Begin(void);
// Turns the camera round its focus, by degrees (+yaw: to the left, +pitch:
// up). 0 if it couldn't go there: it stayed where it was.
int IOSFreeze_Orbit(float yawDeg, float pitchDeg);
// Moves the camera and its focus across the view, as fractions of the
// view's height (right, down): what is seen follows the fingers
void IOSFreeze_Pan(float right, float down);
// Zooms in (factor > 1) or out
void IOSFreeze_Zoom(float factor);
// Coming in from a wall is at once; with smoothing on, going back out
// glides (the touches turn it on; the cinematic burst wants exact places)
void IOSFreeze_SetSmooth(int bOn);
// Once a frame, before it is drawn
void IOSFreeze_Frame(void);
// Back to the game, which goes on from exactly where it stopped
void IOSFreeze_End(void);
int IOSFreeze_IsActive(void);

#ifdef __cplusplus
}
#endif

#endif // IOSFREEZE_H
