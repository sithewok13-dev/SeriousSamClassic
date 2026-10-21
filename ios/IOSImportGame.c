/* The "Game files needed" screen for Sam FE and Sam SE: what each game needs
   and what the screen says. The screen itself (iosImport.m) and the copying
   (iosImportCore.c) are the same files as in the Jedi Knight port. */
#include <stdio.h>
#include <string.h>
#include "iosImport.h"

const char *IOS_DocumentsDir(void);

/* The First Encounter keeps its levels in a Levels folder; The Second
   Encounter's are in SE1_00_Levels.gro. */
static const char *const _aFERequired[] = { "1_00c.gro", "1_00_music.gro", "Levels/", NULL };
static const char *const _aFECopy[] = { "*.gro", "Levels", "Help", "Demos", NULL };
static const char *const _aSERequired[] = { "SE1_00.gro", "SE1_00_Levels.gro", NULL };
static const char *const _aSECopy[] = { "*.gro", "Levels", "Help", NULL };

static const iosImportGame _gameFE = { _aFERequired, _aFECopy, NULL, NULL, "SE1_00_Levels.gro" };
static const iosImportGame _gameSE = { _aSERequired, _aSECopy, NULL, NULL, "1_00c.gro" };

static const iosImportText _textFE = {
  "The First Encounter",
  "Sam FE needs your game files",
  "Sam FE plays your own copy of Serious Sam: The First Encounter, from GOG or Steam. "
  "Copy the game's folder from your computer to iCloud Drive (a .zip of it or a USB stick works too), "
  "then tap Choose Game Files and pick it. The app copies only what it needs. You only do this once.",
  "On your computer, open the folder The First Encounter is installed in:\n\n"
  "GOG Galaxy: select the game, open the menu next to Play, then Manage installation > Show folder.\n\n"
  "Steam: right-click the game, then Manage > Browse local files.\n\n"
  "Not sure? Search your computer for 1_00_music.gro: the folder it's in is the one.\n\n"
  "Copy that whole folder into iCloud Drive (or zip it first, or put it on a USB stick). "
  "Then, on this iPhone, tap Choose Game Files and pick that folder or .zip.",
  "These are The Second Encounter's files. They go in the Sam SE app. This app needs The First Encounter.",
  "Pick the folder The First Encounter is installed in (the one with the .gro files and the Levels folder), or a .zip of it.",
};

static const iosImportText _textSE = {
  "The Second Encounter",
  "Sam SE needs your game files",
  "Sam SE plays your own copy of Serious Sam: The Second Encounter, from GOG or Steam. "
  "Copy the game's folder from your computer to iCloud Drive (a .zip of it or a USB stick works too), "
  "then tap Choose Game Files and pick it. The app copies only what it needs. You only do this once.",
  "On your computer, open the folder The Second Encounter is installed in:\n\n"
  "GOG Galaxy: select the game, open the menu next to Play, then Manage installation > Show folder.\n\n"
  "Steam: right-click the game, then Manage > Browse local files.\n\n"
  "Not sure? Search your computer for SE1_00_Levels.gro: the folder it's in is the one.\n\n"
  "Copy that whole folder into iCloud Drive (or zip it first, or put it on a USB stick). "
  "Then, on this iPhone, tap Choose Game Files and pick that folder or .zip.",
  "These are The First Encounter's files. They go in the Sam FE app. This app needs The Second Encounter.",
  "Pick the folder The Second Encounter is installed in (the one with the .gro files), or a .zip of it.",
};

/* Shows the screen until the game's files are in the app's folder (called
   when the engine can't find them). Returns 1 once they are. */
int IOS_ImportGameData(int bSE)
{
  char strDocs[1024];
  snprintf(strDocs, sizeof(strDocs), "%s", IOS_DocumentsDir());
  size_t len = strlen(strDocs);
  if (len > 1 && strDocs[len - 1] == '/') strDocs[len - 1] = 0;
  return iosImport_RunScreen(bSE ? &_gameSE : &_gameFE, bSE ? &_textSE : &_textFE, strDocs, strDocs);
}
