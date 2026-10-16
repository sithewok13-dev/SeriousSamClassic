/* The touch controls' cheat (sithewok): what the overlay and the game tell
   each other. The cheat itself works in the player entity (Player.es,
   IOSCheat_* functions, patch_engine.py), driven by bits in the player's
   actions, so it reaches the game the same way in single player and in a
   network game, and only ever acts on the player who sent them. */
#ifndef IOSCHEAT_H
#define IOSCHEAT_H

/* The player's action bits (Player.es: PLACT_*), sent every tick while on.
   Bits 20-22 are free in both games. */
#define IOSCHEAT_PLACT_ON     (1UL << 20) /* the cheat: god mode, everything given, ammo kept full, pits caught */
#define IOSCHEAT_PLACT_FLY    (1UL << 21) /* flying (forward goes where you look; JUMP rises, CROUCH sinks) */
#define IOSCHEAT_PLACT_NOCLIP (1UL << 22) /* through walls (flying too) */

/* The word, typed in the console. Typing it switches the cheat on or off. */
#define IOSCHEAT_WORD "sithewok"

#ifdef __cplusplus
extern "C" {
#endif

/* Set by the app (the main loop) at startup, called by the game's libraries:
   the bits for local player 0's actions this tick (Game.cpp), and the word
   typed in the console (Console.cpp). A pointer, so the game's libraries
   don't link against the app. */
extern unsigned long (*IOSCheat_pfnActionBits)(void);
extern void (*IOSCheat_pfnTyped)(void);

#ifdef __cplusplus
}
#endif

#endif
