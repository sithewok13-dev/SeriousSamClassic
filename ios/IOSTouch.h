/* On-screen touch controls for iOS, for both games.

   A UIKit overlay (IOSTouch.m) sits on top of SDL's game view while a
   single-player game is being played. It turns touches into:
     - a floating move stick under the left thumb (anywhere in the left 42%
       of the screen): analog movement, straight into the player's action
     - drag-to-look anywhere else, fed in as mouse movement (so the game's
       mouse settings apply: Options > Controls' SENSITIVITY, INVERT LOOK
       and SMOOTH AXIS; the look speed is set for MOUSE ACCELERATION on, as
       it is by default)
     - buttons. Bottom right: FIRE, with CROUCH / USE / JUMP on an arc around
       it; ZOOM beside FIRE while the sniper rifle is held and BOMB beside
       JUMP while there are serious bombs, saying how many (both Second
       Encounter only). USE works switches, but never opens NETRICSA (however
       quickly it is tapped again, and whatever the player's settings say)
       or works the sniper scope: only ZOOM does. Dragging on any of these
       also looks, except BOMB, which goes off as the finger lifts on it (so
       a look swipe can't waste a bomb). Top left: NEXT and PREV weapon,
       below the score. Top right: QUICK SAVE, QUICK LOAD and MENU.
     - the HUD's messages box (an envelope and how many unread, blinking
       while there are some): a tap marks every message read, so it stops
       blinking; with nothing unread it stays, dim and still (on PC it goes
       away), as the way into NETRICSA. Held until a ring round it fills
       (0.45 s, as MENU's), it opens NETRICSA, once the finger is known to
       have stayed on, as QUICK SAVE (the ring keeps to that time, so a full
       ring always means NETRICSA). A
       finger that slides off it does neither; one kept still where it
       landed stays on it while a new message drops the box down a little
       and back. A button next to it keeps its own touches; the box is live
       only while the HUD draws it (Options > HUD's messages on), in a game
       being played.
     - QUICK SAVE and QUICK LOAD only go off when held: a ring round the
       button fills while it is held (0.3 s), and lifting before it is full
       does nothing. Each saves or loads once the finger is known to have
       stayed on it that long (a frame after the ring fills): once, however
       many fingers hold it. A finger that slides off doesn't save or load
       at all, even if it comes back on. Held together, the one found
       complete first goes off and ends the other's hold (QUICK SAVE if both
       are found complete in the same frame, e.g. after a long one): never a
       save and a load from one press.
     - MENU: a tap opens the menu (as the finger lifts). Held until its ring
       fills (0.45 s), it opens a small tray just under it instead: the
       keyboard (opens the console with the iOS keyboard, for cheats;
       tapping it again closes both) and FPS (shows or hides a frame rate
       readout by QUICK SAVE, remembered across launches). Slide the
       held thumb onto one, or lift and tap it; a touch anywhere else closes
       the tray.
   Buttons act on the player directly, not through key bindings, so they
   work whatever keys are bound. While the game is paused (e.g. after the app
   was in the background) only RESUME and MENU show; while the console is
   open only MENU, lit up: a tap on it (or its tray's keyboard) closes the
   console and the iOS keyboard, back to the game. In menus, NETRICSA,
   demos and while a level loads the overlay hides, so touches reach SDL as
   mouse clicks as before; patch_engine.py makes the menus and NETRICSA act
   on what a tap lands on (a mouse hovers there first, a finger doesn't), and
   a tap ends a wait for a key to bind or the typing of a name. If SDL's
   window is recreated the overlay follows it.

   The HUD and the game's other text on the screen keep inside
   IOSTouch_GetHudFrame: clear of the screen's rounded corners, the home
   indicator and a notch. Two things that blink sit in the HUD's top row
   instead of under FIRE at the bottom right as on PC: the unread messages
   box, right of the high score, and the Second Encounter's power-ups,
   between the score and the high score. The row of small ammo boxes at the
   bottom right (every ammo type, and the serious bombs) isn't drawn: the
   current weapon's ammo shows at the bottom middle as on PC, and BOMB
   counts the bombs.

   Threads: IOSTouch_Update and IOSTouch_Hide run on the main thread,
   IOSTouch_ReadInput on the game's input thread (SDLTimer, once per game
   tick), IOSTouch_TakeLook on either. */

#ifndef SE_INCL_IOSTOUCH_H
#define SE_INCL_IOSTOUCH_H

#ifdef __cplusplus
extern "C" {
#endif

/* What the game is doing (IOSTouch_Update), which decides what shows */
enum {
  IOSTOUCH_HIDDEN = 0, /* menus, NETRICSA, demos, loading: touches are mouse clicks */
  IOSTOUCH_GAMEPLAY,   /* a single-player game is being played */
  IOSTOUCH_CONSOLE,    /* the console is open over the game: only MENU (and its tray) */
  IOSTOUCH_PAUSED,     /* the game is paused: RESUME and MENU */
};

/* What the HUD shows, so the buttons keep clear of it and the context
   buttons know when to show. Rectangles are x0, y0, x1, y1 as fractions of
   the screen, empty if x1 <= x0. */
typedef struct IOSTouchHud {
  int bValid;       /* the HUD was drawn lately (the rest is from then) */
  float afScore[4];    /* the score box, top left */
  float afHiScore[4];  /* the high score box, top middle */
  float afMessages[4]; /* the unread messages box, where it sits when it shows (top row) */
  float afMessagesNow[4]; /* ...where it was drawn this time: a new message drops it down a little for a while */
  int bMessages;    /* the messages box is drawn (dim with nothing unread) */
  int ctMessages;   /* the unread messages it shows */
  int bSniper;      /* holding the sniper rifle (Second Encounter) */
  int ctBombs;      /* serious bombs (Second Encounter) */
} IOSTouchHud;

/* What the player asked for, carried out by the main loop (IOSTouch_Update's result) */
enum {
  IOSTOUCH_REQ_MENU      = 1 << 0, /* Escape: the menu (with the console open: just close the console) */
  IOSTOUCH_REQ_CONSOLE   = 1 << 1, /* open or close the console (MENU's tray) */
  IOSTOUCH_REQ_QUICKSAVE = 1 << 2,
  IOSTOUCH_REQ_QUICKLOAD = 1 << 3,
  IOSTOUCH_REQ_RESUME    = 1 << 4, /* unpause */
  IOSTOUCH_REQ_READMESSAGES = 1 << 5, /* mark every NETRICSA message read (a tap on the unread messages box) */
};

/* Buttons as the game reads them once per tick (IOSTouchInput.ulButtons) */
enum {
  IOSTOUCH_FIRE       = 1 << 0,
  IOSTOUCH_USE        = 1 << 1, /* use. Never NETRICSA, never the sniper scope */
  IOSTOUCH_JUMP       = 1 << 2,
  IOSTOUCH_CROUCH     = 1 << 3,
  IOSTOUCH_NEXTWEAPON = 1 << 4,
  IOSTOUCH_PREVWEAPON = 1 << 5,
  IOSTOUCH_ZOOM       = 1 << 6, /* sniper scope (plain use) */
  IOSTOUCH_BOMB       = 1 << 7, /* serious bomb (one press per tap) */
  IOSTOUCH_COMPUTER   = 1 << 8, /* NETRICSA (one press: the unread messages box held) */
  IOSTOUCH_NUMBUTTONS = 9
};
typedef struct IOSTouchInput {
  float fMoveX;           /* move stick: -1..1, right is + */
  float fMoveY;           /* -1..1, forward is + */
  unsigned int ulButtons; /* IOSTOUCH_FIRE... held (or a quick tap) for this tick */
} IOSTouchInput;

/* Main thread, once per frame: shows or hides the overlay for iMode, follows
   the SDL window (an SDL_Window *) and lays out around the HUD.
   ulFramesDrawn: the game's count of frames drawn, which the FPS readout
   counts. Returns the IOSTOUCH_REQ_* the player asked for since the last
   call. */
int IOSTouch_Update(void *pSDLWindow, int iMode, const IOSTouchHud *pHud, unsigned int ulFramesDrawn);
/* Main thread: where the HUD lays itself out, and the game's messages, clock
   and stats: the screen less its rounded corners and the home indicator (see
   IOSTouch.m), as x0, y0, x1, y1 fractions of the screen. The whole screen
   until IOSTouch_Update has seen SDL's view. */
void IOSTouch_GetHudFrame(float afFrame[4]);
/* Main thread: hide now (a level is loading); the next update shows it again */
void IOSTouch_Hide(void);
/* Game input thread, once per game tick: the stick and the buttons. A button
   tapped too quickly for any tick to see it is reported for two ticks, then
   up for one. */
void IOSTouch_ReadInput(IOSTouchInput *pInput);
/* Either thread: look movement since the last call, in mouse counts */
void IOSTouch_TakeLook(float *pfDX, float *pfDY);

/* Provided by the HUD (Entities Common/HUD.cpp), main thread */
void IOS_GetHudState(IOSTouchHud *pHud);
/* Provided by NETRICSA (GameMP/Computer.cpp), main thread: marks every
   message of the first local player read (IOSTOUCH_REQ_READMESSAGES) */
void IOS_MarkAllMessagesRead(void);

#ifdef __cplusplus
}
#endif

#endif /* SE_INCL_IOSTOUCH_H */
