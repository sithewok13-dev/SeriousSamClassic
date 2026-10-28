/* The touch controls' cheat (sithewok): what the app does for it, on the
   main thread. The cheat itself is in the player entity (IOSCheat.h). */
#ifndef IOSCHEATGAME_H
#define IOSCHEATGAME_H

#ifdef __cplusplus
extern "C" {
#endif

/* Whether the game being played lets this phone's player cheat: alone, or a
   network game whose host allows it (ALLOW CHEATS) */
int IOSCheatGame_Allowed(void);

/* The campaign's levels, in order (single player only: 0 otherwise) */
int IOSCheatGame_NumLevels(void);
/* Level iLevel's (1..IOSCheatGame_NumLevels()) name, as the game's level
   info gives it, and its file (Levels/...wld), cut to fit the buffers.
   Whether there is such a level. */
int IOSCheatGame_LevelInfo(int iLevel, char *strName, int ctName, char *strFile, int ctFile);
/* The level being played (1..IOSCheatGame_NumLevels(); 0: none of them) */
int IOSCheatGame_CurrentLevel(void);
/* Starts level iLevel (1..IOSCheatGame_NumLevels()) as a new single-player
   game at the same difficulty. Whether it started. */
int IOSCheatGame_GoToLevel(int iLevel);

/* One of Sam's lines from the game's own files (a different one from last
   time), at the game's sound effects volume */
void IOSCheatGame_PlaySound(void);

/* Changes whenever a level starts or is loaded (this phone's player is a
   new one then) */
unsigned int IOSCheatGame_World(void);

/* How many falls the cheat has caught for this phone's player (the view
   flashes softly each time the count goes up) */
unsigned int IOSCheatGame_Catches(void);

#ifdef __cplusplus
}
#endif

#endif
