/* iOS glue for Serious Engine 1: where files live. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
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
