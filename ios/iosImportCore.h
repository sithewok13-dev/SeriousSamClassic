// Added: entire file. The game-file import behind the "Game files needed"
// screen (iosImport.m), in plain C so it can be tested off the phone and shared
// with the owner's other ports (Serious Sam keeps an identical copy).
//
// The player picks folders, single files or .zip files (from iCloud Drive, a
// USB stick, the app's own folder...). Everything picked is indexed as one
// virtual folder; the game is the shallowest folder in it that holds every
// required file (names match without case, as in the engine). Only the game's
// own items are copied, into a staging folder first, then moved into place, so
// a copy that stops halfway never counts as installed.

#ifndef _PLATFORM_IOS_IOSIMPORTCORE_H
#define _PLATFORM_IOS_IOSIMPORTCORE_H

#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

// What one game needs. All lists end with NULL; paths use '/', any case.
typedef struct iosImportGame {
    const char* const* required;     // files the game can't start without; "name/" is a
                                     // folder that must have files in it
    const char* const* copy;         // top-level items to copy from the game's folder;
                                     // "*.ext" means files with that ending directly in it
    const char* const* keep;         // saves and profiles: brought along only if the
                                     // destination has none yet, never overwritten
    const char* const* optional;     // pairs: path (folder or file), what it is ("music")
    const char* otherMarker;         // a file only the sibling game has (wrong-game check)
} iosImportGame;

typedef struct iosImportIndex iosImportIndex;

enum {
    IOSIMPORT_OK = 0,
    IOSIMPORT_NOTHING,     // none of the game's files anywhere
    IOSIMPORT_PARTIAL,     // some of them; missing[] says which
    IOSIMPORT_WRONG_GAME,  // the sibling game's files
    IOSIMPORT_BAD_ZIP,     // a .zip it can't read (damaged, encrypted, unusual)
};

#define IOSIMPORT_MAX_MISSING 16

typedef struct iosImportPlan {
    int status;
    char root[1024];          // the game's folder inside the picked items ("" = top)
    int64_t totalBytes;       // what will be copied
    int fileCount;
    int bAllLocal;            // every file is a plain file, so it can be moved, not copied
    int missingCount;
    const char* missing[IOSIMPORT_MAX_MISSING];          // required paths not found
    int missingOptionalCount;
    const char* missingOptional[IOSIMPORT_MAX_MISSING];  // labels ("music") not found
    char badZip[512];         // the .zip that couldn't be read
} iosImportPlan;

// Opens a source file for reading; the app passes one that first downloads an
// iCloud file (NSFileCoordinator). NULL uses fopen.
typedef FILE* (*iosImportOpenFn)(const char* path, void* user);
// Called about every megabyte while copying, and once at the end.
typedef void (*iosImportProgressFn)(int64_t done, int64_t total, const char* name, void* user);

iosImportIndex* iosImport_NewIndex(void);
void iosImport_FreeIndex(iosImportIndex* idx);

// Adds a picked item as <its name> in the virtual folder: a folder (read up to
// a few levels deep), a .zip (its contents, under the zip's name without
// ".zip"), or a single file. pOpen is used to read a .zip's directory.
// Returns 0 if it couldn't be read at all.
int iosImport_AddItem(iosImportIndex* idx, const char* path, iosImportOpenFn pOpen, void* user);

// Adds what's in pDir (the app's own Files folder), each item under its own
// name, skipping the names in pSkip (NULL-ended): finds game files a player
// put in the wrong place.
void iosImport_AddFolderContents(iosImportIndex* idx, const char* pDir, const char* const* pSkip, iosImportOpenFn pOpen, void* user);

// Finds the game in what was added. pDest is where it will go (for "keep").
void iosImport_Plan(iosImportIndex* idx, const iosImportGame* game, const char* pDest, iosImportPlan* plan);

// Copies the plan into pStaging (emptied first), then moves it into pDest,
// replacing files of the same name there and leaving everything else alone.
// bMove renames plain files instead of copying them (same volume only).
// Returns NULL on success, or a short reason.
const char* iosImport_Install(iosImportIndex* idx, const iosImportGame* game, const iosImportPlan* plan,
                              const char* pStaging, const char* pDest, int bMove,
                              iosImportOpenFn pOpen, iosImportProgressFn pProgress, void* user);

// Deletes a folder and everything in it (the staging folder).
void iosImport_RemoveTree(const char* path);

#ifdef __cplusplus
}
#endif

#endif // _PLATFORM_IOS_IOSIMPORTCORE_H
