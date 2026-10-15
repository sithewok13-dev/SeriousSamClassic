// A selfie of one, three or five photos: see IOSSelfieShots.h.

#include "IOSSelfieShots.h"
#include "IOSSelfie.h"
#include "IOSCapture.h"
#include "IOSPhotos.h"

#include <stdio.h>

// The first photo waits this long once everyone is posed (a frame or two
// drawn posed, and the moment the buttons take to go); the others are taken
// as soon as the one before is (one frame each). The last stays on screen
// IOSSELFIESHOTS_SHOW. A photo that hasn't been taken IOSSELFIESHOTS_GIVEUP
// after it was due (the frame read failed, or no room to save it) ends it.
#define IOSSELFIESHOTS_SETTLE 0.35
#define IOSSELFIESHOTS_SHOW   0.9
#define IOSSELFIESHOTS_GIVEUP 3.0

static int _iState = IOSSELFIESHOTS_IDLE;
static int _ctWanted = 0;  // photos wanted
static int _ctTaken = 0;   // photos taken
static int _bAsked = 0;    // the current one is asked for
static int _bPosed = 0;    // the selfie was set up (as the first frame was drawn)
static double _tStart = 0, _tStage = 0;
static double _tLast = 0;  // the last tick (how long the game was held)

int IOSSelfieShots_Start(int numShots, double now)
{
  if (_iState != IOSSELFIESHOTS_IDLE) return IOSSELFIESHOTS_CANT;
  if (numShots < 1) numShots = 1;
  if (numShots > IOSSELFIESHOTS_MAX) numShots = IOSSELFIESHOTS_MAX;
  // Room for all of them in the capture budget before starting, so a
  // selfie never waits frozen for the saving to catch up
  if (IOSCapture_IsPending() || !IOSCapture_HasRoom(IOSCAPTURE_CLEAN, numShots)) return IOSSELFIESHOTS_BUSY;
  if (!IOSSelfie_Begin()) return IOSSELFIESHOTS_CANT;
  _ctWanted = numShots;
  _ctTaken = 0;
  _bAsked = 0;
  _bPosed = 0;
  _tStart = _tStage = _tLast = now;
  _iState = IOSSELFIESHOTS_TAKING;
  // (several: one message for them all, and numbered names)
  if (numShots > 1) IOSPhotos_SetBatch(1);
  return IOSSELFIESHOTS_STARTED;
}

int IOSSelfieShots_Tick(double now)
{
  if (_iState == IOSSELFIESHOTS_IDLE) return IOSSELFIESHOTS_IDLE;
  _tLast = now;
  // (the selfie ended from elsewhere: no more photos of the game's own view)
  if (!IOSSelfie_IsActive()) {
    IOSSelfieShots_Stop();
    return _iState;
  }
  // As the first frame was drawn, there turned out to be no room for the
  // camera: no selfie
  if (IOSSelfie_Failed()) {
    IOSSelfieShots_Stop();
    IOS_ShowCameraMessage("Can't take a selfie here");
    return _iState;
  }
  if (!IOSSelfie_IsPosed()) {
    // (not drawn yet; it would be by now if the game drew at all)
    if (now - _tStart >= IOSSELFIESHOTS_GIVEUP) {
      IOSSelfieShots_Stop();
      IOS_ShowCameraMessage("Couldn't take the selfie");
    }
    return _iState;
  }
  if (!_bPosed) {
    _bPosed = 1;
    _tStage = now; // (the first photo's wait starts now)
  }
  if (_iState == IOSSELFIESHOTS_SHOWING) {
    if (now - _tStage >= IOSSELFIESHOTS_SHOW) IOSSelfieShots_Stop();
    return _iState;
  }
  // Taken (a frame read it), or given up on by the capture (it says why)
  if (_bAsked && !IOSCapture_IsPending()) {
    _bAsked = 0;
    _ctTaken++;
    _tStage = now;
    if (_ctTaken >= _ctWanted) {
      _iState = IOSSELFIESHOTS_SHOWING;
      return _iState;
    }
    IOSSelfie_Repose(); // the next one, posed afresh (drawn so in the next frame)
  }
  if (!_bAsked) {
    const int bDue = _ctTaken > 0 || now - _tStage >= IOSSELFIESHOTS_SETTLE;
    if (bDue && IOSCapture_Request(IOSCAPTURE_CLEAN, IOSCAPTURE_MODE_SELFIE)) {
      _bAsked = 1;
      _tStage = now;
    }
  }
  if (now - _tStage >= IOSSELFIESHOTS_GIVEUP + (_ctTaken ? 0.0 : IOSSELFIESHOTS_SETTLE)) {
    const int taken = _ctTaken, num = _ctWanted;
    IOSSelfieShots_Stop();
    // (the saving says what it saved; this, that the rest weren't taken)
    char msg[64];
    if (taken) snprintf(msg, sizeof(msg), "Took %d of %d selfie photos", taken, num);
    else snprintf(msg, sizeof(msg), "Couldn't take the selfie");
    IOS_ShowCameraMessage(msg);
  }
  return _iState;
}

void IOSSelfieShots_Stop(void)
{
  if (_iState == IOSSELFIESHOTS_IDLE) return;
  if (_bAsked && IOSCapture_IsPending()) IOSCapture_Cancel();
  _bAsked = 0;
  _iState = IOSSELFIESHOTS_IDLE;
  IOSSelfie_End();
  // (the game held from the start to now, the last photo's showing too)
  IOSCapture_NoteFreeze(_tLast - _tStart);
  if (_ctWanted > 1) IOSPhotos_SetBatch(0);
}

int IOSSelfieShots_IsActive(void)
{
  return _iState != IOSSELFIESHOTS_IDLE;
}

int IOSSelfieShots_NumTaken(void)
{
  return _ctTaken;
}
