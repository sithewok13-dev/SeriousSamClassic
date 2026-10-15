// A selfie of one, three or five photos (as the Jedi Knight port's
// iosSelfieShots): the selfie (IOSSelfie) set up once, then for each photo
// everyone posed afresh and one clean capture (IOSCapture), as fast as
// frames are drawn and the capture budget allows. The game holds still from
// the first photo to the last, so nothing in the level moves between them.
// The last photo stays on screen a moment, then everything is put back and
// the game goes on. The touch overlay starts it, ticks it once a frame
// before the frame is drawn and hides its buttons while it runs; the Linux
// test rig drives the same code. Plain C, on the game's thread.

#ifndef IOSSELFIESHOTS_H
#define IOSSELFIESHOTS_H

#ifdef __cplusplus
extern "C" {
#endif

#define IOSSELFIESHOTS_MAX 5

// IOSSelfieShots_Start's answers
#define IOSSELFIESHOTS_STARTED  1
#define IOSSELFIESHOTS_CANT     0  // no selfie here (the player dead, a cutscene...)
#define IOSSELFIESHOTS_BUSY    -1  // the last photos are still being saved

// What it is doing (IOSSelfieShots_Tick)
#define IOSSELFIESHOTS_IDLE    0
#define IOSSELFIESHOTS_TAKING  1   // posing and taking the photos
#define IOSSELFIESHOTS_SHOWING 2   // the last photo, on screen a moment

// Starts a selfie of numShots photos (clamped to 1..IOSSELFIESHOTS_MAX), at
// now (seconds, any steady clock). Where it turns out it can't be taken
// after all (there is no room for the camera: found as the first frame is
// drawn), it says so and ends by itself.
int IOSSelfieShots_Start(int numShots, double now);
// Once a frame, before it is drawn. Returns what it is doing; IDLE once all
// is put back (or it gave up).
int IOSSelfieShots_Tick(double now);
// Ends it at once, everything put back (the app going to the background, a
// menu, the overlay going). Safe to call when idle.
void IOSSelfieShots_Stop(void);
int IOSSelfieShots_IsActive(void);
// Photos taken so far in this one
int IOSSelfieShots_NumTaken(void);

#ifdef __cplusplus
}
#endif

#endif // IOSSELFIESHOTS_H
