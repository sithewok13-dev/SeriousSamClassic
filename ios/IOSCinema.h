// The cinematic burst (as the Jedi Knight port's iosCinema): the game
// freezes for a moment and five photos are taken as the camera sweeps round
// the action, then the game goes on by itself. The first is exactly what the
// player saw; the other four go round the most interesting thing in front:
// an enemy being fought, a shot in flight or an explosion (with a boss or an
// enemy close by, the player and it are both in the shots, seen from the
// side). With nothing about, it goes round the player. The sweep takes the
// side with the most room. Built on IOSFreeze. On the game's thread.

#ifndef IOSCINEMA_H
#define IOSCINEMA_H

#ifdef __cplusplus
extern "C" {
#endif

#define IOSCINEMA_SHOTS 5

#define IOSCINEMA_STARTED  1
#define IOSCINEMA_CANT     0  // no freeze here
#define IOSCINEMA_BUSY    -1  // the last photos are still being saved

#define IOSCINEMA_IDLE    0
#define IOSCINEMA_TAKING  1
#define IOSCINEMA_SHOWING 2

int IOSCinema_Start(double now);
// Once a frame, before it is drawn: what it is doing (IDLE once it is over)
int IOSCinema_Tick(double now);
void IOSCinema_Stop(void);
int IOSCinema_IsActive(void);
int IOSCinema_NumTaken(void);

#ifdef __cplusplus
}
#endif

#endif // IOSCINEMA_H
