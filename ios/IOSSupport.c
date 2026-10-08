/* iOS glue for Serious Engine 1: where files live. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "SDL.h"

/* The app's Documents folder, with a trailing slash. The Files app shows it
   as "On My iPhone > <app name>" (UIFileSharingEnabled in Info.plist), which
   is where players drop the game data from their own copy of the game. */
const char *IOS_DocumentsDir(void)
{
  static char strDir[1024] = "";
  if (strDir[0] == 0) {
    const char *strHome = getenv("HOME");
    snprintf(strDir, sizeof(strDir), "%s/Documents/", strHome ? strHome : ".");
    mkdir(strDir, 0755);
  }
  return strDir;
}

/* stdout and stderr go to Output.log in the same folder, next to
   SeriousSam.log: gl4es reports there what the GPU supports and any shaders
   it fails to build, and the engine logs what it draws (see GfxLibrary.cpp). */
void IOS_StartOutputLog(void)
{
  char strPath[1100];
  snprintf(strPath, sizeof(strPath), "%sOutput.log", IOS_DocumentsDir());
  if (freopen(strPath, "w", stdout) != NULL) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    dup2(fileno(stdout), fileno(stderr));
  }
  setenv("LIBGL_LOGSHADERERROR", "1", 1);
}

static long FileSize(const char *strPath)
{
  struct stat st;
  return (stat(strPath, &st) == 0) ? (long) st.st_size : -1;
}

/* Copy a file shipped inside the app bundle (engine data that is part of the
   open-source release, e.g. SE1_10b.gro) next to the player's game data. */
void IOS_InstallBundledFile(const char *strName)
{
  char strSrc[1024], strDst[1024];
  char *strBase = SDL_GetBasePath();
  if (strBase == NULL) return;
  snprintf(strSrc, sizeof(strSrc), "%s%s", strBase, strName);
  snprintf(strDst, sizeof(strDst), "%s%s", IOS_DocumentsDir(), strName);
  SDL_free(strBase);

  long slSrc = FileSize(strSrc);
  if (slSrc < 0 || slSrc == FileSize(strDst)) return;  // missing, or already current

  FILE *fSrc = fopen(strSrc, "rb");
  FILE *fDst = fSrc ? fopen(strDst, "wb") : NULL;
  if (fSrc && fDst) {
    char buf[64 * 1024];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), fSrc)) > 0) {
      fwrite(buf, 1, n, fDst);
    }
  }
  if (fDst) fclose(fDst);
  if (fSrc) fclose(fSrc);
}

/* iOS kills apps that touch OpenGL while in the background, so the main
   loop parks here (pausing a single-player game first) until we're back. */
static volatile int _bInBackground = 0;

static int SDLCALL IOS_AppEventWatch(void *pUser, SDL_Event *pEvent)
{
  (void) pUser;
  switch (pEvent->type) {
  case SDL_APP_WILLENTERBACKGROUND:
  case SDL_APP_DIDENTERBACKGROUND:
    _bInBackground = 1;
    break;
  case SDL_APP_DIDENTERFOREGROUND:
    _bInBackground = 0;
    break;
  default:
    break;
  }
  return 1;
}

int IOS_IsInBackground(void)
{
  static int bWatching = 0;
  if (!bWatching) {
    SDL_AddEventWatch(IOS_AppEventWatch, NULL);
    bWatching = 1;
  }
  return _bInBackground;
}

void IOS_WaitForForeground(void)
{
  while (_bInBackground) {
    SDL_Delay(100);
    SDL_PumpEvents();
  }
}
