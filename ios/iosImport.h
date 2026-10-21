// Added: entire file. The "Game files needed" screen: shown at launch when the
// game's files aren't in the app's folder, it lets the player pick the game
// folder or a .zip of it (iCloud Drive, a USB stick, this iPhone...) and copies
// what the game needs into place (iosImportCore.c). Game files a player already
// put somewhere else in the app's folder are found and moved into place.
// Generic: the game and its words come from the caller, so the owner's other
// ports share this file unchanged.

#ifndef _PLATFORM_IOS_IOSIMPORT_H
#define _PLATFORM_IOS_IOSIMPORT_H

#include "iosImportCore.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct iosImportText {
    const char* gameName;   // "Jedi Knight" (short, used in sentences)
    const char* title;      // "Jedi Knight needs your game files"
    const char* body;       // what to do, a few sentences
    const char* help;       // "Where do I find them?": where the game is installed
    const char* wrongGame;  // the sibling game's files were picked
    const char* whatToPick; // "Pick the folder the game is installed in..."
} iosImportText;

// Shows the screen until the files are in pDest, then returns 1 (0 if it
// couldn't be shown at all). pDocs is the app's Files folder, searched first.
// Main thread only; blocks, running the main run loop, like SDL's message boxes.
int iosImport_RunScreen(const iosImportGame* game, const iosImportText* text, const char* pDocs, const char* pDest);

#ifdef __cplusplus
}
#endif

#endif // _PLATFORM_IOS_IOSIMPORT_H
