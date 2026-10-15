// The CAMERA button's photos: saved to Photos (add-only), or to the app's
// Files folder (Screenshots). See IOSPhotos.m; IOSPhotos_SaveCapture is in
// IOSCapture.h.

#ifndef IOSPHOTOS_H
#define IOSPHOTOS_H

#ifdef __cplusplus
extern "C" {
#endif

// Asks for add-only Photos access if it was never asked: 1 if the system's
// question is now up (done is called on the main thread once it is
// answered), 0 if it was answered before (done isn't called).
int IOSPhotos_AskAccess(void (*done)(void));

// While a burst (or a selfie of several) is going (1): the message saying
// what was saved waits for its end, so it comes once for the whole of it.
void IOSPhotos_SetBatch(int bOn);

#ifdef __cplusplus
}
#endif

#endif // IOSPHOTOS_H
