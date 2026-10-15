// Action Freeze's camera, for the cinematic burst (IOSCinema): it set up
// (the first frame drawn), and its orbit -- a focus, the camera's heading and
// pitch looking at it (degrees), how far from it and how near it may come
// (metres: round a thing, out of it). See
// IOSFreeze.cpp. C++, in the game library.

#ifndef IOSFREEZECAM_H
#define IOSFREEZECAM_H

int IOSFreeze_IsReady(void);
void IOSFreeze_GetOrbit(FLOAT3D &vFocus, FLOAT &fYaw, FLOAT &fPitch, FLOAT &fDist, FLOAT &fMinDist);
// Puts the camera there exactly (nearer, where the level is in the way): 0
// if there is no place for it that way (it stays where it was)
int IOSFreeze_SetOrbit(const FLOAT3D &vFocus, FLOAT fYaw, FLOAT fPitch, FLOAT fDist, FLOAT fMinDist);
// How far from the focus the camera could be that way (and where): -1 if
// nowhere; nothing moves
FLOAT IOSFreeze_ProbeAt(const FLOAT3D &vFocus, FLOAT fYaw, FLOAT fPitch, FLOAT fDist, FLOAT fMinDist, FLOAT3D &vPos);

#endif // IOSFREEZECAM_H
