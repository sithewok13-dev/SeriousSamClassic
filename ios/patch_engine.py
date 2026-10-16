#!/usr/bin/env python3
"""Adds the PLATFORM_IOS code paths to both games' sources.
Idempotent: re-running it on patched files does nothing."""
import pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

def sub(path, old, new, marker):
    s = path.read_text()
    if marker in s:
        return
    assert s.count(old) == 1, f"{path}: anchor not unique/found: {old[:60]!r}"
    path.write_text(s.replace(old, new, 1))

for game in ("SamTFE", "SamTSE"):
    src = ROOT / game / "Sources"

    # ---------------------------------------------------------------- paths
    p = src / "Engine/Engine.cpp"
    sub(p, "  _fnmUserDir = CTString(buf);\n",
"""  _fnmUserDir = CTString(buf);
#ifdef PLATFORM_IOS
  // iOS: game data and settings live in the app's Documents folder,
  // which the Files app shows as "On My iPhone > <app name>".
  {
    _fnmApplicationPath = CTString(IOS_DocumentsDir());
    _fnmUserDir = _fnmApplicationPath;
    IOS_InstallBundledFile("SE1_10b.gro");
    IOS_InstallBundledFile("ModEXT.txt");
  }
#endif
""", "IOS_DocumentsDir")

    sub(p, "  // print info on the started application\n",
"""#ifdef PLATFORM_IOS
  {
    CTString strTest = (strGameID == "serioussamse") ? "SE1_00_Levels.gro" : "1_00_music.gro";
    if (!_pFileSystem->Exists((const char *)(_fnmApplicationPath + strTest))) {
      FatalError(TRANSV("Game data not found.\\n\\n"
        "Copy the files from your own copy of the game (all .gro files, plus the Help and Levels folders) "
        "into Files > On My iPhone > this app, then start it again.\\n\\nMissing: %s"),
        (const char *) strTest);
    }
  }
#endif
  // print info on the started application
""", 'strTest = (strGameID == "serioussamse")')

    sub(p, '#include <Engine/Base/FileSystem.h>\n',
"""#include <Engine/Base/FileSystem.h>
#ifdef PLATFORM_IOS
extern "C" const char *IOS_DocumentsDir(void);
extern "C" void IOS_InstallBundledFile(const char *strName);
#endif
""", 'extern "C" const char *IOS_DocumentsDir')

    # ------------------------------------------------------------ OpenGL/gl4es
    p = src / "Engine/Graphics/SDL/SDLOpenGL.cpp"
    sub(p, '#include "SDL.h"\n',
'''#include "SDL.h"

#ifdef PLATFORM_IOS
// iOS only has OpenGL ES; gl4es translates the engine's desktop GL calls.
#include <gl4esinit.h>
#include <dlfcn.h>
// Resolve real GLES entry points from the system framework only. A plain
// SDL_GL_GetProcAddress would find gl4es' own glXxx symbols in our binary.
static void *IOS_GLESProcAddress(const char *name)
{
  static void *hGLES = NULL;
  if (hGLES == NULL) {
    hGLES = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY | RTLD_LOCAL);
  }
  return hGLES ? dlsym(hGLES, name) : NULL;
}
static void IOS_MainFBSize(int *w, int *h)
{
  SDL_GL_GetDrawableSize(SDL_GL_GetCurrentWindow(), w, h);
}
#define SE_GL_GETPROC(name) gl4es_GetProcAddress(name)
#else
#define SE_GL_GETPROC(name) SDL_GL_GetProcAddress(name)
#endif
''', "IOS_GLESProcAddress")
    sub(p, "    p##name = (output (__stdcall*) inputs) SDL_GL_GetProcAddress(strName); \\\n",
           "    p##name = (output (__stdcall*) inputs) SE_GL_GETPROC(strName); \\\n",
        "SE_GL_GETPROC(strName)")
    sub(p, "    return(SDL_GL_GetProcAddress(procname));\n",
           "    return(SE_GL_GETPROC(procname));\n", "SE_GL_GETPROC(procname)")
    sub(p, "  // prepare functions\n  OGL_SetFunctionPointers_t(gl_hiDriver);\n",
"""#ifdef PLATFORM_IOS
  {
    static BOOL bGL4ESReady = FALSE;
    if (!bGL4ESReady) {
      set_getprocaddress(IOS_GLESProcAddress);
      set_getmainfbsize(IOS_MainFBSize);
      initialize_gl4es();
      bGL4ESReady = TRUE;
    }
  }
#endif
  // prepare functions
  OGL_SetFunctionPointers_t(gl_hiDriver);
""", "initialize_gl4es();")
    sub(p, "  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);\n",
"""  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
#ifdef PLATFORM_IOS
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
#endif
""", "SDL_GL_CONTEXT_PROFILE_ES")

    # flush gl4es' batched draws before presenting
    p = src / "Engine/Graphics/GfxLibrary.cpp"
    sub(p, "    SDL_GL_SwapWindow((SDL_Window *) pvp->vp_hWnd);\n",
"""#ifdef PLATFORM_IOS
    pglFlush();
#endif
    SDL_GL_SwapWindow((SDL_Window *) pvp->vp_hWnd);
""", "    pglFlush();\n#endif\n    SDL_GL_SwapWindow")

    # ----------------------------------------------------------------- window
    p = src / "SeriousSam/MainWindow.cpp"
    sub(p, "  unsigned int _uFlags = SDL_WINDOW_OPENGL;\n",
"""  unsigned int _uFlags = SDL_WINDOW_OPENGL;
#ifdef PLATFORM_IOS
  _uFlags |= SDL_WINDOW_FULLSCREEN | SDL_WINDOW_BORDERLESS;  // whole screen, no status bar
#endif
""", "whole screen, no status bar")

    # ------------------------------------------------- static-link symbol fixes
    # These four helpers are used by the Shaders module too; as plain
    # "inline" they are never emitted, which only goes unnoticed with
    # lazily-bound shared libraries.
    p = src / "Engine/Ska/RMRender.cpp"
    for fn in ("MatrixVectorToMatrix12(Matrix12 &m12,const FLOATmatrix3D &m, const FLOAT3D &v)",
               "TransformVertex(GFXVertex &v, const Matrix12 &m)",
               "RotateVector(FLOAT3 &v, const Matrix12 &m)",
               "MatrixTranspose(Matrix12 &r, const Matrix12 &m)"):
        sub(p, "\ninline void " + fn + "\n", "\nvoid " + fn + "\n", "\nvoid " + fn + "\n")
    # file-local flag that clashes with GameAgent's when linked together
    for cam in src.glob("Game*/Camera.cpp"):
        sub(cam, "\nBOOL _bInitialized;\n", "\nstatic BOOL _bInitialized;\n", "static BOOL _bInitialized;")
    # the engine already defines these; the executable only needs them
    # when the engine is a separate shared library
    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, "#ifdef PLATFORM_UNIX\nENGINE_API FLOAT _fWeaponFOVAdjuster;",
           "#if defined(PLATFORM_UNIX) && !defined(STATICALLY_LINKED)\nENGINE_API FLOAT _fWeaponFOVAdjuster;",
           "!defined(STATICALLY_LINKED)\nENGINE_API FLOAT _fWeaponFOVAdjuster;")

    # SDL provides the real main() on iOS and calls ours as SDL_main
    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, "#include <fcntl.h>\n",
           "#include <fcntl.h>\n#ifdef PLATFORM_IOS\n#include <SDL_main.h>\n#endif\n", "#include <SDL_main.h>")

    # ------------------------------------------- static-link module lookups
    # GetInstance(NULL) means "the main program": everything is linked in.
    p = src / "Engine/Base/Unix/UnixDynamicLoader.cpp"
    sub(p, "void CUnixDynamicLoader::DoOpen(const char *lib)\n{\n",
"""void CUnixDynamicLoader::DoOpen(const char *lib)
{
    if (lib == NULL) {  // the main program (everything is linked in statically)
        module = ::dlopen(NULL, RTLD_LAZY | RTLD_GLOBAL);
        if (module == NULL) {
            SetError();
        }
        return;
    }
""", "if (lib == NULL) {  // the main program")
    p = src / "Engine/Sound/SoundDecoder.cpp"
    sub(p, "       _hOV = CDynamicLoader::GetInstance(VORBISLIB);\n",
"""       #ifdef STATICALLY_LINKED
       _hOV = CDynamicLoader::GetInstance(NULL);
       #else
       _hOV = CDynamicLoader::GetInstance(VORBISLIB);
       #endif
""", "_hOV = CDynamicLoader::GetInstance(NULL);")
    sub(p, '      _hAmp11lib = CDynamicLoader::GetInstance("amp11lib");\n',
"""      #ifdef STATICALLY_LINKED
      _hAmp11lib = CDynamicLoader::GetInstance(NULL);
      #else
      _hAmp11lib = CDynamicLoader::GetInstance("amp11lib");
      #endif
""", "_hAmp11lib = CDynamicLoader::GetInstance(NULL);")

    # TFE: lighting tables defined in a header included by both the Game and
    # Entities modules; give each its own copy as the separate libraries did.
    p = src / "Entities/Common/LightFixes.h"
    if p.exists():
        t = p.read_text()
        if "static FLOAT _f" not in t:
            import re as _re
            t, n = _re.subn(r"^FLOAT (_f\w+Coordinates\[)", r"static FLOAT \1", t, flags=_re.M)
            assert n == 10, n
            p.write_text(t)

    # park the main loop while the app is in the background (no GL allowed)
    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, "#include <SDL_main.h>\n#endif\n",
"""#include <SDL_main.h>
extern "C" int IOS_IsInBackground(void);
extern "C" void IOS_WaitForForeground(void);
#endif
""", "IOS_IsInBackground(void);")
    sub(p, '  while( _bRunning && _fnmModToLoad=="")\n  {\n',
"""  while( _bRunning && _fnmModToLoad=="")
  {
#ifdef PLATFORM_IOS
    if (IOS_IsInBackground()) {
      if (_gmRunningGameMode==GM_SINGLE_PLAYER && !_pNetwork->IsPaused()) {
        _pNetwork->TogglePause();
      }
      IOS_WaitForForeground();
    }
#endif
""", "IOS_WaitForForeground();\n    }")

    # ------------------------------------------------- show every frame
    # UIKit only puts a new frame on screen when its run loop turns. The main
    # loop gets there when it reads input; loading screens never did, so they
    # stayed black.
    p = src / "Engine/Graphics/GfxLibrary.cpp"
    sub(p, "    SDL_GL_SwapWindow((SDL_Window *) pvp->vp_hWnd);\n",
"""    SDL_GL_SwapWindow((SDL_Window *) pvp->vp_hWnd);
#ifdef PLATFORM_IOS
    IOS_LogFrameStats(gl_ctWorldTriangles, gl_ctModelTriangles, gl_ctTotalTriangles);
    SDL_PumpEvents();  // let UIKit show the frame
#endif
""", "SDL_PumpEvents();  // let UIKit show the frame")

    # ----------------------------------------- tap leaves the intro / demos
    # A tap arrives as a left click, which only skips to the next demo; on
    # iOS it is the only input there is, so make it Escape: to the menu.
    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, "      if (msg.message==WM_KEYDOWN && msg.wParam==VK_ESCAPE && \n"
           "        (_gmRunningGameMode==GM_DEMO || _gmRunningGameMode==GM_INTRO)) {\n",
"""#ifdef PLATFORM_IOS
      if (msg.message==WM_LBUTTONDOWN &&
        (_gmRunningGameMode==GM_DEMO || _gmRunningGameMode==GM_INTRO)) {
        msg.message = WM_KEYDOWN;
        msg.wParam = VK_ESCAPE;
      }
#endif
      if (msg.message==WM_KEYDOWN && msg.wParam==VK_ESCAPE && \n        (_gmRunningGameMode==GM_DEMO || _gmRunningGameMode==GM_INTRO)) {
""", "msg.message = WM_KEYDOWN;\n        msg.wParam = VK_ESCAPE;")

    # ---------------------------------------------------- diagnostics log
    # stdout/stderr go to Output.log in Documents (gl4es reports there), plus
    # what the real OpenGL ES under gl4es provides and, once a second, how
    # much got drawn and any GLES errors -- to find why the 3D view is black.
    p = src / "Engine/Engine.cpp"
    sub(p, 'extern "C" void IOS_InstallBundledFile(const char *strName);\n',
           'extern "C" void IOS_InstallBundledFile(const char *strName);\n'
           'extern "C" void IOS_StartOutputLog(void);\n', "IOS_StartOutputLog(void);")
    sub(p, '    IOS_InstallBundledFile("ModEXT.txt");\n  }\n',
           '    IOS_InstallBundledFile("ModEXT.txt");\n    IOS_StartOutputLog();\n  }\n', "    IOS_StartOutputLog();\n")

    p = src / "Engine/Graphics/SDL/SDLOpenGL.cpp"
    sub(p, "  // prepare functions\n  OGL_SetFunctionPointers_t(gl_hiDriver);\n",
"""#ifdef PLATFORM_IOS
  {
    typedef const char *(*GetStringFn)(unsigned int);
    typedef void (*GetIntegervFn)(unsigned int, int *);
    GetStringFn pGetString = (GetStringFn) IOS_GLESProcAddress("glGetString");
    GetIntegervFn pGetIntegerv = (GetIntegervFn) IOS_GLESProcAddress("glGetIntegerv");
    if (pGetString != NULL && pGetIntegerv != NULL) {
      int iDepth = -1, iStencil = -1, iFBO = -1, iW = 0, iH = 0;
      pGetIntegerv(0x0D56, &iDepth);    // GL_DEPTH_BITS
      pGetIntegerv(0x0D57, &iStencil);  // GL_STENCIL_BITS
      pGetIntegerv(0x8CA6, &iFBO);      // GL_FRAMEBUFFER_BINDING
      IOS_MainFBSize(&iW, &iH);
      printf("GLES: %s, %s\\n", pGetString(0x1F01), pGetString(0x1F02));  // GL_RENDERER, GL_VERSION
      printf("GLES: depth %d bits, stencil %d bits, framebuffer %d, drawable %dx%d\\n",
             iDepth, iStencil, iFBO, iW, iH);
      printf("GLES extensions: %s\\n", pGetString(0x1F03));  // GL_EXTENSIONS
    }
  }
#endif
  // prepare functions
  OGL_SetFunctionPointers_t(gl_hiDriver);
""", 'printf("GLES: depth %d bits')

    p = src / "Engine/Graphics/GfxLibrary.cpp"
    sub(p, "#ifdef PLATFORM_UNIX\n#include <SDL.h>\n#endif\n",
"""#ifdef PLATFORM_UNIX
#include <SDL.h>
#endif

#ifdef PLATFORM_IOS
#include <dlfcn.h>
// Once a second, into Output.log: frames drawn, triangles drawn, the
// framebuffer bound and any errors from the real OpenGL ES under gl4es.
static void IOS_LogFrameStats(INDEX ctWorld, INDEX ctModel, INDEX ctTotal)
{
  static Uint32 tmLast = 0;
  static INDEX ctFrames = 0;
  static unsigned int (*pGetError)(void) = NULL;
  static void (*pGetIntegerv)(unsigned int, int *) = NULL;
  static BOOL bLooked = FALSE;
  ctFrames++;
  const Uint32 tmNow = SDL_GetTicks();
  if (tmNow - tmLast < 1000) return;
  if (!bLooked) {
    void *hGLES = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY | RTLD_LOCAL);
    if (hGLES != NULL) {
      pGetError = (unsigned int (*)(void)) dlsym(hGLES, "glGetError");
      pGetIntegerv = (void (*)(unsigned int, int *)) dlsym(hGLES, "glGetIntegerv");
    }
    bLooked = TRUE;
  }
  int iFBO = -1;
  if (pGetIntegerv != NULL) pGetIntegerv(0x8CA6, &iFBO);  // GL_FRAMEBUFFER_BINDING
  printf("[%u ms] %d frames, triangles: world %d, models %d, total %d, framebuffer %d, GLES errors:",
         (unsigned) tmNow, (int) ctFrames, (int) ctWorld, (int) ctModel, (int) ctTotal, iFBO);
  INDEX ctErrors = 0;
  for (; pGetError != NULL && ctErrors < 8; ctErrors++) {
    const unsigned int iError = pGetError();
    if (iError == 0) break;
    printf(" 0x%04X", iError);
  }
  printf(ctErrors == 0 ? " none\\n" : "\\n");
  ctFrames = 0;
  tmLast = tmNow;
}
#endif
""", "IOS_LogFrameStats(INDEX ctWorld")

    # ------------------------------------------- float->int like x86, on arm64
    # Converting an out-of-range float (or +-inf, NaN) to an int is undefined
    # in C++. x86 gives INT_MIN (0x80000000), which these spots were written
    # around; arm64 saturates (+inf -> INT_MAX) instead. In BoxToGrid that made
    # the infinite movement box of a Moving Brush (two in 1_0_InTheLastEpisode)
    # span 64001x64001 collision cells, searched on every move: the first game
    # tick never finished and the screen stayed black. The existing guards are
    # for 32-bit ARM (__arm__) only. These do what x86 did, on every CPU, and
    # give the same results as before on x86.
    p = src / "Engine/World/WorldCollisionGrid.cpp"
    sub(p, "// find grid box from float coordinates\n",
"""// Float to grid coordinate as on x86: out of range (and inf/NaN) gives
// INT_MIN, which the clamps below turn into GRID_MIN -- one cell
static inline INDEX GridCoord(double d)
{
  return (d > -2147483648.0 && d < 2147483648.0) ? INDEX(d) : INDEX(0x80000000);
}

// find grid box from float coordinates
""", "static inline INDEX GridCoord(double d)")
    sub(p, """  iMinX = INDEX(floor(fMinX/GRID_CELLSIZE));
  iMinZ = INDEX(floor(fMinZ/GRID_CELLSIZE));
  iMaxX = INDEX(ceil(fMaxX/GRID_CELLSIZE));
  iMaxZ = INDEX(ceil(fMaxZ/GRID_CELLSIZE));
""", """  iMinX = GridCoord(floor(fMinX/GRID_CELLSIZE));
  iMinZ = GridCoord(floor(fMinZ/GRID_CELLSIZE));
  iMaxX = GridCoord(ceil(fMaxX/GRID_CELLSIZE));
  iMaxZ = GridCoord(ceil(fMaxZ/GRID_CELLSIZE));
""", "iMinX = GridCoord(floor(fMinX/GRID_CELLSIZE));")

    # the same pattern for a terrain's rectangle (its guard is __arm__-only too)
    p = src / "Engine/Terrain/TerrainMisc.cpp"
    if p.exists():
        t = p.read_text()
        if "TerrainCoord(" not in t:
            anchor = "  Rect rc;\n  if(!bFixSize) {\n"
            assert t.count(anchor) == 1, p
            t = t.replace(anchor, """  // Float to int as on x86: out of range (and inf/NaN) gives INT_MIN, which
  // the clamps turn into 0
  #define TerrainCoord(d) ((((double)(d)) > -2147483648.0 && ((double)(d)) < 2147483648.0) ? (INDEX)(d) : (INDEX)0x80000000)
""" + anchor, 1)
            for old, new in (("Clamp((INDEX)(bbox.minvect(1)-0),", "Clamp(TerrainCoord(bbox.minvect(1)-0),"),
                             ("Clamp((INDEX)(bbox.minvect(3)-0),", "Clamp(TerrainCoord(bbox.minvect(3)-0),"),
                             ("Clamp((INDEX)ceil(bbox.maxvect(1)+1),", "Clamp(TerrainCoord(ceil(bbox.maxvect(1)+1)),"),
                             ("Clamp((INDEX)ceil(bbox.maxvect(3)+1),", "Clamp(TerrainCoord(ceil(bbox.maxvect(3)+1)),"),
                             ("Clamp((INDEX)(bbox.maxvect(1)+0),", "Clamp(TerrainCoord(bbox.maxvect(1)+0),"),
                             ("Clamp((INDEX)(bbox.maxvect(3)+0),", "Clamp(TerrainCoord(bbox.maxvect(3)+0),")):
                assert t.count(old) >= 1, (p, old)
                t = t.replace(old, new)
            p.write_text(t)

    # FloatToInt's portable branch (the one arm64 uses): x86's fistp gives
    # INT_MIN for out-of-range values too (the light layer mixer hits it)
    p = src / "Engine/Math/Functions.h"
    sub(p, """  float addToRound = copysignf(0.5f, f); // copy f's signbit to 0.5 => if f<0 then addToRound = -0.5, else 0.5
  return((SLONG) (f + addToRound));
""", """  float addToRound = copysignf(0.5f, f); // copy f's signbit to 0.5 => if f<0 then addToRound = -0.5, else 0.5
  const float fRounded = f + addToRound;
  // out of range (and NaN): INT_MIN, as x86's fistp gives; arm64 would saturate
  if (!(fRounded > -2147483648.0f && fRounded < 2147483648.0f)) return (SLONG)0x80000000;
  return((SLONG) fRounded);
""", "const float fRounded = f + addToRound;")

    # rain/snow: a negative float to ULONG wraps on x86, but is 0 on arm64
    for parts in src.glob("Entities*/Common/Particles.cpp"):
        t = parts.read_text()
        if "ULONG(SLONG(vPos(" not in t:
            n = t.count("(ULONG(vPos(3)+iZ))") + t.count("(ULONG(vPos(1)+iX))")
            assert n >= 2, parts
            t = t.replace("(ULONG(vPos(3)+iZ))", "(ULONG(SLONG(vPos(3)+iZ)))")
            t = t.replace("(ULONG(vPos(1)+iX))", "(ULONG(SLONG(vPos(1)+iX)))")
            parts.write_text(t)

    # ------------------------------------------------- no tilt-as-joystick
    # SDL offers the accelerometer as joystick 1 ("iOS Accelerometer", 3 axes),
    # so tilting the phone could feed the game's joystick axes
    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, "  if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) == -1)\n",
"""#ifdef PLATFORM_IOS
  SDL_SetHint(SDL_HINT_ACCELEROMETER_AS_JOYSTICK, "0");
#endif
  if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) == -1)
""", "SDL_HINT_ACCELEROMETER_AS_JOYSTICK")

    # ------------------------------------------------- touch controls
    # The overlay is ios/IOSTouch.m; these feed what it reads into the game.
    # Buttons and the move stick go straight into the player's action for the
    # tick, so they work whatever keys are bound (Controls/System/Common.ctl
    # with the quick save/load keys isn't part of the game data on the phone).
    p = src / "GameMP/Game.cpp"
    sub(p, "void CControls::CreateAction(const CPlayerCharacter &pc, CPlayerAction &paAction, BOOL bPreScan)\n",
"""#ifdef PLATFORM_IOS
#include "IOSTouch.h"
// The player's button bits, as in Player.es (PLACT_*; they are not in a
// header). The First Encounter has no sniper rifle or serious bomb, and uses
// bits 9-13 to select weapons.
#define IOS_PLACT_FIRE        (1L<<0)
#define IOS_PLACT_WEAPON_NEXT (1L<<2)
#define IOS_PLACT_WEAPON_PREV (1L<<3)
#define IOS_PLACT_USE         (1L<<5)
#define IOS_PLACT_COMPUTER    (1L<<6)
#ifdef FIRST_ENCOUNTER
#define IOS_PLACT_USE_HELD    0
#define IOS_PLACT_SNIPER_USE  0
#define IOS_PLACT_FIREBOMB    0
#define IOS_PLACT_USE_NOZOOM  0
#else
#define IOS_PLACT_USE_HELD    (1L<<9)
#define IOS_PLACT_SNIPER_USE  (1L<<12)
#define IOS_PLACT_FIREBOMB    (1L<<13)
#define IOS_PLACT_USE_NOZOOM  (1L<<19)  // added to Player.es for iOS
#endif

// The touch controls' buttons as the player's button bits for this tick.
// USE is a plain use, once as it goes down: unlike the default Use key
// (ctl_bUseOrComputer), it never opens NETRICSA -- not when tapped again
// within ctl_tmComputerDoubleClick, nor on a single click if the player's
// settings say so (a thumb did that by accident). NETRICSA is a hold on the
// HUD's messages box (the envelope), which comes as IOSTOUCH_COMPUTER: the
// Computer key. Nor does USE work the sniper scope, which that key does
// when there is nothing to use: it sends no USE_HELD or SNIPER_USE, and
// USE_NOZOOM with its press. ZOOM is the scope: plain use (with the sniper
// rifle: scope on/off, held: zoom in). A keyboard's or controller's own Use
// key still works as on PC.
// NETRICSA's press gets its tick to itself: the player takes a new use in
// the same tick instead (with something to use, or the sniper rifle), so a
// USE or ZOOM press that comes with it waits for the next tick.
static ULONG IOS_TouchButtonActions(ULONG ulTouch)
{
  static ULONG ulTouchLast = 0;
  static ULONG ulHeldBack = 0;  // USE or ZOOM pressed with NETRICSA's press, for the next tick
  const ULONG ulNew = ulTouch&~ulTouchLast;
  const ULONG ulHoldBack = (ulNew&IOSTOUCH_COMPUTER) ? (ulNew&(IOSTOUCH_USE|IOSTOUCH_ZOOM)) : 0;
  ulTouch = (ulTouch&~ulHoldBack)|ulHeldBack;
  ulHeldBack = ulHoldBack;
  ULONG ulActions = 0;
  if (ulTouch&IOSTOUCH_FIRE)       ulActions |= IOS_PLACT_FIRE;
  if (ulTouch&IOSTOUCH_NEXTWEAPON) ulActions |= IOS_PLACT_WEAPON_NEXT;
  if (ulTouch&IOSTOUCH_PREVWEAPON) ulActions |= IOS_PLACT_WEAPON_PREV;
  if (ulTouch&IOSTOUCH_BOMB)       ulActions |= IOS_PLACT_FIREBOMB;
  if (ulTouch&IOSTOUCH_ZOOM)       ulActions |= IOS_PLACT_USE|IOS_PLACT_USE_HELD|IOS_PLACT_SNIPER_USE;
  if (ulTouch&IOSTOUCH_COMPUTER)   ulActions |= IOS_PLACT_COMPUTER;
  // USE just pressed
  if ((ulTouch&IOSTOUCH_USE) && !(ulTouchLast&IOSTOUCH_USE)) {
    ulActions |= IOS_PLACT_USE|IOS_PLACT_USE_NOZOOM;
  }
  ulTouchLast = ulTouch;
  return ulActions;
}
#endif

void CControls::CreateAction(const CPlayerCharacter &pc, CPlayerAction &paAction, BOOL bPreScan)
""", "static ULONG IOS_TouchButtonActions(")
    sub(p, """  // execute all button-action shell commands
  if (!bPreScan) {
    DoButtonActions();
  }
  //CPrintF("creating: prescan %d, x:%g\\n", bPreScan, paAction.pa_aRotation(1));

  // make the player class create the action packet
  ctl_ComposeActionPacket(pc, paAction, bPreScan);
}
""", """#ifdef PLATFORM_IOS
  // touch controls (first local player): the move stick as movement axes,
  // JUMP and CROUCH as up and down -- before the player's speeds apply
  IOSTouchInput tiTouch;
  memset(&tiTouch, 0, sizeof(tiTouch));
  if (!bPreScan && ctl_iCurrentPlayerLocal==0) {
    IOSTouch_ReadInput(&tiTouch);
    paAction.pa_vTranslation(1) += tiTouch.fMoveX;
    paAction.pa_vTranslation(3) -= tiTouch.fMoveY;
    if (tiTouch.ulButtons&IOSTOUCH_JUMP)   paAction.pa_vTranslation(2) += 1.0f;
    if (tiTouch.ulButtons&IOSTOUCH_CROUCH) paAction.pa_vTranslation(2) -= 1.0f;
  }
#endif

  // execute all button-action shell commands
  if (!bPreScan) {
    DoButtonActions();
  }
  //CPrintF("creating: prescan %d, x:%g\\n", bPreScan, paAction.pa_aRotation(1));

  // make the player class create the action packet
  ctl_ComposeActionPacket(pc, paAction, bPreScan);
#ifdef PLATFORM_IOS
  // and its buttons, whatever keys are bound
  if (!bPreScan && ctl_iCurrentPlayerLocal==0) {
    paAction.pa_ulButtons |= IOS_TouchButtonActions(tiTouch.ulButtons);
  }
#endif
}
""", "IOSTouch_ReadInput(&tiTouch);")
    # Tilt aiming: the degrees the phone turned go straight into the first
    # local player's rotation, every frame in the prescan (shown at once with
    # sharp turning) and every tick, before the player's packet adds them to
    # its absolute angle -- not through the mouse counts, whose filter and
    # precision options aren't linear (and invert, sensitivity, smoothing
    # and the axis bindings apply there), so at 1.0x the view turns as far
    # as the phone whatever they are set to. The prescan doesn't set
    # ctl_iCurrentPlayerLocal, so the first local player is told by its
    # character.
    sub(p, """    if (tiTouch.ulButtons&IOSTOUCH_CROUCH) paAction.pa_vTranslation(2) -= 1.0f;
  }
#endif
""", """    if (tiTouch.ulButtons&IOSTOUCH_CROUCH) paAction.pa_vTranslation(2) -= 1.0f;
  }
  // tilt aiming (first local player, in the prescan every frame and in the
  // tick): the degrees the phone turned (+ left) and tilted (+ up) since the
  // last call, straight into the rotation -- the mouse settings never apply
  if (_pGame->gm_lpLocalPlayers[0].lp_pplsPlayerSource!=NULL
   && &pc==&_pGame->gm_apcPlayers[_pGame->gm_lpLocalPlayers[0].lp_iPlayer]) {
    float fGyroYaw = 0.0f, fGyroPitch = 0.0f;
    IOSTouch_TakeGyro(&fGyroYaw, &fGyroPitch);
    paAction.pa_aRotation(1) += fGyroYaw;
    paAction.pa_aRotation(2) += fGyroPitch;
  }
#endif
""", "IOSTouch_TakeGyro(")

    # The touch controls' USE never works the sniper scope (ZOOM does): with
    # the rifle held, the Use key toggles the scope when there is nothing to
    # use, and USE sits where a thumb hits it by accident. Game.cpp sends
    # PLACT_USE_NOZOOM with its press. ECC takes no preprocessor lines in
    # function bodies, so the bit is 0 except on iOS and the code testing it
    # is on every platform, doing nothing there.
    if game == "SamTSE":
        p = src / "EntitiesMP/Player.es"
        sub(p, "#define PLACT_SELECT_WEAPON_MASK  (0x1FL<<PLACT_SELECT_WEAPON_SHIFT)\n",
"""#define PLACT_SELECT_WEAPON_MASK  (0x1FL<<PLACT_SELECT_WEAPON_SHIFT)
#ifdef PLATFORM_IOS
// With PLACT_USE from the touch controls' USE (GameMP/Game.cpp): that use never
// works the sniper scope (their ZOOM button does).
#define PLACT_USE_NOZOOM          (1L<<19)
#else
#define PLACT_USE_NOZOOM          0
#endif
""", "#define PLACT_USE_NOZOOM")
        sub(p, """    else if (!bSomethingToUse)
    {
""", """    // nothing to use: the sniper scope on or off (not for the iOS touch controls' USE)
    else if (!bSomethingToUse && !(ulButtonsNow&PLACT_USE_NOZOOM))
    {
""", "!bSomethingToUse && !(ulButtonsNow&PLACT_USE_NOZOOM)")

    # The touch controls' USE doesn't open NETRICSA (a hold on the HUD's unread
    # messages box does), so the hint shown until NETRICSA was first opened
    # says so. (A #define, as ECC takes no preprocessor lines in function
    # bodies: on the desktop the same string as before.)
    p = src / ("EntitiesMP/Player.es" if game == "SamTSE" else "Entities/Player.es")
    sub(p, "#define PLACT_SELECT_WEAPON_MASK  (0x1FL<<PLACT_SELECT_WEAPON_SHIFT)\n",
"""#define PLACT_SELECT_WEAPON_MASK  (0x1FL<<PLACT_SELECT_WEAPON_SHIFT)
#ifdef PLATFORM_IOS
// (the touch controls' USE doesn't open NETRICSA: holding the HUD's messages box does, so the hint
// shows only while the HUD draws it)
#define STR_READ_MESSAGE_HINT "Hold the envelope at the top to read the message!"
#define READ_MESSAGE_HINT_AND && hud_bShowMessages && hud_bShowInfo
#else
#define STR_READ_MESSAGE_HINT "Press USE to read the message!"
#define READ_MESSAGE_HINT_AND
#endif
""", "#define STR_READ_MESSAGE_HINT")
    sub(p, '          TRANS("Press USE to read the message!"), 5.0f, MSS_NONE);\n',
           '          TRANS(STR_READ_MESSAGE_HINT), 5.0f, MSS_NONE);\n', "TRANS(STR_READ_MESSAGE_HINT)")
    sub(p, "      if (!m_bComputerInvoked && GetSP()->sp_bSinglePlayer) {\n",
           "      if (!m_bComputerInvoked && GetSP()->sp_bSinglePlayer READ_MESSAGE_HINT_AND) {\n", "sp_bSinglePlayer READ_MESSAGE_HINT_AND")

    # drag-to-look: more mouse movement, before the mouse settings apply
    p = src / "Engine/Base/SDL/SDLInput.cpp"
    sub(p, "#include <Engine/Base/ErrorReporting.h>\n",
"""#include <Engine/Base/ErrorReporting.h>

#ifdef PLATFORM_IOS
#include "IOSTouch.h"
#endif
""", '#include "IOSTouch.h"')
    sub(p, "    FLOAT fDY = FLOAT( mouse_relative_y );\n",
"""    FLOAT fDY = FLOAT( mouse_relative_y );
#ifdef PLATFORM_IOS
    // the touch controls' drag-to-look, as more mouse movement
    {
      float fTouchDX = 0.0f, fTouchDY = 0.0f;
      IOSTouch_TakeLook(&fTouchDX, &fTouchDY);
      fDX += fTouchDX;
      fDY += fTouchDY;
    }
#endif
""", "IOSTouch_TakeLook(&fTouchDX, &fTouchDY);")

    # Touches that land on SDL's own view (while the overlay is hidden: menus,
    # NETRICSA, a loading screen) come as SDL's touch-mouse. Those are menu
    # clicks (PeekMessage still hands them out) and nothing else: a finger
    # that came down on a loading screen and stays down must not fire (Mouse
    # Button 1) or turn the view (SDL's relative mouse state counts it too)
    # once the game is back. A real mouse or trackpad still does both. The
    # fingers that come down are counted, for the menu's wait for a key to
    # bind (see the menus by touch, below).
    sub(p, "static Sint16 mouse_relative_y = 0;\n",
"""static Sint16 mouse_relative_y = 0;
#ifdef PLATFORM_IOS
// mouse movement for looking, from a real mouse or trackpad only
static SDL_atomic_t _iIOSMouseDX, _iIOSMouseDY;
// fingers that came down on SDL's own view (the menus), for the menu's wait
// for a key to bind: a touch is no button it could bind
ENGINE_API INDEX inp_ctIOSTouchPresses = 0;
#endif
""", "static SDL_atomic_t _iIOSMouseDX, _iIOSMouseDY;")
    sub(p, "        case SDL_MOUSEMOTION:\n            mouse_relative_x += event->motion.xrel;\n",
"""        case SDL_MOUSEMOTION:
#ifdef PLATFORM_IOS
            if (event->motion.which == SDL_TOUCH_MOUSEID) break;  // a touch: no mouse look
            SDL_AtomicAdd(&_iIOSMouseDX, event->motion.xrel);
            SDL_AtomicAdd(&_iIOSMouseDY, event->motion.yrel);
#endif
            mouse_relative_x += event->motion.xrel;
""", "if (event->motion.which == SDL_TOUCH_MOUSEID) break;")
    sub(p, "        case SDL_MOUSEBUTTONUP:\n            if (event->button.button <= 5) {\n",
"""        case SDL_MOUSEBUTTONUP:
#ifdef PLATFORM_IOS
            if (event->button.which == SDL_TOUCH_MOUSEID) {  // a touch: a menu click, not a mouse button
              if (event->button.state == SDL_PRESSED) inp_ctIOSTouchPresses++;
              break;
            }
#endif
            if (event->button.button <= 5) {
""", "if (event->button.which == SDL_TOUCH_MOUSEID) {  // a touch")
    sub(p, "  SDL_GetRelativeMouseState(&iMx, &iMy);\n",
"""  SDL_GetRelativeMouseState(&iMx, &iMy);
#ifdef PLATFORM_IOS
  iMx = SDL_AtomicSet(&_iIOSMouseDX, 0);
  iMy = SDL_AtomicSet(&_iIOSMouseDY, 0);
#endif
""", "iMx = SDL_AtomicSet(&_iIOSMouseDX, 0);")
    sub(p, "    SDL_GetRelativeMouseState(NULL, NULL);\n    #endif\n",
"""    SDL_GetRelativeMouseState(NULL, NULL);
    #endif
#ifdef PLATFORM_IOS
    SDL_AtomicSet(&_iIOSMouseDX, 0);
    SDL_AtomicSet(&_iIOSMouseDY, 0);
#endif
""", "    SDL_AtomicSet(&_iIOSMouseDX, 0);\n")

    # the iOS keyboard types a word picked from its suggestions as one text
    # event; hand out all of its characters, not just the first
    p = src / "Engine/Base/SDL/SDLEvents.cpp"
    sub(p, "    SDL_Event sdlevent;\n    while (SE_SDL_InputEventPoll(&sdlevent))\n",
"""#ifdef PLATFORM_IOS
    // the rest of a text event that brought several characters at once
    static char strTextLeft[SDL_TEXTINPUTEVENT_TEXT_SIZE] = "";
    static int iTextLeft = 0;
    if (strTextLeft[iTextLeft] != 0) {
        SDL_zerop(msg);
        msg->message = SDL_TEXTINPUT;
        msg->wParam = strTextLeft[iTextLeft++];
        return TRUE;
    }
#endif
    SDL_Event sdlevent;
    while (SE_SDL_InputEventPoll(&sdlevent))
""", "static char strTextLeft[SDL_TEXTINPUTEVENT_TEXT_SIZE]")
    sub(p, "                msg->wParam = sdlevent.text.text[0];  // !!! FIXME: dropping characters!\n",
"""                msg->wParam = sdlevent.text.text[0];  // !!! FIXME: dropping characters!
#ifdef PLATFORM_IOS
                if (sdlevent.text.text[0] != 0) {
                    SDL_strlcpy(strTextLeft, sdlevent.text.text + 1, sizeof(strTextLeft));
                    iTextLeft = 0;
                }
#endif
""", "SDL_strlcpy(strTextLeft, sdlevent.text.text + 1")
    # a press or release says where it was, as on Windows: a finger moves
    # SDL's pointer there with it, and by the time the message is handled
    # SDL's mouse state may be at a later touch (the menus by touch, below)
    sub(p, "            case SDL_MOUSEBUTTONDOWN:\n            case SDL_MOUSEBUTTONUP:\n",
"""            case SDL_MOUSEBUTTONDOWN:
            case SDL_MOUSEBUTTONUP:
#ifdef PLATFORM_IOS
                msg->lParam = (
                                ((sdlevent.button.y << 16) & 0xFFFF0000) |
                                ((sdlevent.button.x      ) & 0x0000FFFF)
                              );
#endif
""", "((sdlevent.button.y << 16) & 0xFFFF0000)")

    # the main loop tells the overlay what the game is doing, once a frame,
    # and carries out what the player asked for on it
    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, 'extern "C" void IOS_WaitForForeground(void);\n#endif\n',
           'extern "C" void IOS_WaitForForeground(void);\n#include "IOSTouch.h"\n#endif\n', '#include "IOSTouch.h"')
    sub(p, "// automaticaly manage pause toggling\nstatic void UpdatePauseState(void)\n",
"""#ifdef PLATFORM_IOS
// A key press for the message loop, as if typed
static void IOS_PushKey(SDL_Keycode iKey)
{
  SDL_Event ev;
  SDL_zero(ev);
  ev.type = SDL_KEYDOWN;
  ev.key.windowID = SDL_GetWindowID((SDL_Window *) _hwndMain);
  ev.key.state = SDL_PRESSED;
  ev.key.keysym.sym = iKey;
  ev.key.keysym.scancode = SDL_GetScancodeFromKey(iKey);
  SDL_PushEvent(&ev);
  ev.type = SDL_KEYUP;
  ev.key.state = SDL_RELEASED;
  SDL_PushEvent(&ev);
}

// Once a frame: tells the touch controls what the game is doing, and carries
// out what the player asked for on them
static void IOS_UpdateTouchControls(void)
{
  // gameplay controls only while a single-player game is being played; in
  // menus, NETRICSA, demos and the intro touches are mouse clicks
  const BOOL bComputer = !(_pGame->gm_csComputerState==CS_OFF || _pGame->gm_csComputerState==CS_ONINBACKGROUND);
  const BOOL bConsoleUp = (_pGame->gm_csConsoleState==CS_ON || _pGame->gm_csConsoleState==CS_TURNINGON);
  int iMode = IOSTOUCH_HIDDEN;
  if (_gmRunningGameMode==GM_SINGLE_PLAYER && _pGame->gm_bGameOn && !bMenuActive && !bMenuRendering && !bComputer) {
    if (bConsoleUp || _pGame->gm_csConsoleState==CS_TURNINGOFF) {
      iMode = IOSTOUCH_CONSOLE;
    } else if (_pGame->gm_csConsoleState==CS_OFF && !IsIconic(_hwndMain)) {
      // paused (after the app was in the background): only Pause resumes.
      // (Not waiting for _pInput->IsInputEnabled(): UpdateInputEnabledState
      // turns the game's input back on later in the frame the console or
      // NETRICSA closed in, and the controls would blink off for that frame.)
      iMode = _pNetwork->IsPaused() ? IOSTOUCH_PAUSED : IOSTOUCH_GAMEPLAY;
    }
  }
  IOSTouchHud hud;
  IOS_GetHudState(&hud);
  // the frames drawn so far (one per SwapBuffers), for the FPS readout
  const int iRequests = IOSTouch_Update(_hwndMain, iMode, &hud, (unsigned int)_pGfx->GetFrameNumber());

  // only what the buttons showing now can ask for. MENU (and the keyboard
  // in its tray) show whenever the overlay does. With the console open, MENU
  // closes just the console (F1, as the tray's keyboard does), back to the
  // game -- Escape would close it and open the menu as well.
  BOOL bToggleConsole = (iRequests&IOSTOUCH_REQ_CONSOLE) && iMode!=IOSTOUCH_HIDDEN;
  if ((iRequests&IOSTOUCH_REQ_MENU) && iMode!=IOSTOUCH_HIDDEN) {
    if (iMode==IOSTOUCH_CONSOLE && bConsoleUp) {
      bToggleConsole = TRUE;
    } else {
      IOS_PushKey(SDLK_ESCAPE);
    }
  }
  if (bToggleConsole) {
    IOS_PushKey(SDLK_F1);
  }
  if ((iRequests&IOSTOUCH_REQ_RESUME) && iMode==IOSTOUCH_PAUSED) {
    // the pause only goes off on the next game tick: don't put it back meanwhile
    static DOUBLE tmResumed = -100.0;
    const DOUBLE tmNow = _pTimer->GetHighPrecisionTimer().GetSeconds();
    if (tmNow>tmResumed+0.5) {
      _pNetwork->TogglePause();
      tmResumed = tmNow;
    }
  }
  if ((iRequests&IOSTOUCH_REQ_QUICKSAVE) && iMode==IOSTOUCH_GAMEPLAY) {
    _pShell->SetINDEX("gam_bQuickSave", 1);  // the game saves it this frame
  }
  if ((iRequests&IOSTOUCH_REQ_QUICKLOAD) && iMode==IOSTOUCH_GAMEPLAY) {
    // loading stops the game first, so a missing quicksave would end it
    if (FileExists(_pGame->GetQuickSaveName(FALSE))) {
      _pShell->SetINDEX("gam_bQuickLoad", 1);
    } else {
      CPrintF(TRANS("No quicksave yet\\n"));
    }
  }
  if ((iRequests&IOSTOUCH_REQ_READMESSAGES) && iMode==IOSTOUCH_GAMEPLAY) {
    IOS_MarkAllMessagesRead();  // the HUD's messages box stops blinking (and dims)
  }
}
#endif

// automaticaly manage pause toggling
static void UpdatePauseState(void)
""", "static void IOS_UpdateTouchControls(void)")
    sub(p, "      IOS_WaitForForeground();\n    }\n#endif\n",
           "      IOS_WaitForForeground();\n    }\n    IOS_UpdateTouchControls();\n#endif\n",
        "    IOS_UpdateTouchControls();\n")

    # ------------------------------------------------- the menus by touch
    # A finger on SDL's own view (the overlay hides in the menus and NETRICSA)
    # comes as a left click, but unlike a mouse it never hovered first: SDL
    # moves the pointer there and presses in the same event pump, and the menu
    # only works out what is under the pointer as it draws, after the frame's
    # messages. So a tap went to whatever the previous one had left focused
    # (OPTIONS opened HIGH SCORES), sliders took the old spot, and options
    # such as INVERT LOOK could not be set. The menu now finds and focuses
    # what is under the finger as it lands; NETRICSA learns where it is. Both
    # take the spot from the press itself (SDLEvents.cpp, above): SDL's
    # pointer may already be at a later touch waiting in the queue.
    p = src / "SeriousSam/Menu.h"
    sub(p, "void MenuOnMouseMove(PIX pixI, PIX pixJ);\n",
"""void MenuOnMouseMove(PIX pixI, PIX pixJ);
#ifdef PLATFORM_IOS
void MenuOnTouchDown(PIX pixI, PIX pixJ);
void MenuKeepSettings(void);
#endif
""", "void MenuOnTouchDown(PIX pixI, PIX pixJ);")
    p = src / "SeriousSam/Menu.cpp"
    sub(p, "static CTimerValue _tvInitialization;\n",
"""#ifdef PLATFORM_IOS
// A finger lands on the menu: SDL moves the pointer there and presses the
// button together, before the next frame works out which gadget is under the
// pointer (DoMenu) -- so find and focus it now, or the press goes to the
// gadget the previous touch left focused (or is dropped). For a mouse, which
// has hovered there already, this changes nothing. pixI, pixJ: where the
// press is, from its message (SDL's pointer may be at a later touch by now).
void MenuOnTouchDown(PIX pixI, PIX pixJ)
{
  extern CDrawPort *pdp;
  if (pgmCurrentMenu==NULL || pdp==NULL) return;
  POINT pt;
  pt.x = pixI;
  pt.y = pixJ;
  extern INDEX sam_bWideScreen;
  if (sam_bWideScreen) {
    const PIX pixHeight = pdp->GetHeight();
    pt.y -= (LONG) ((pixHeight/0.75f-pixHeight)/2);
  }
  // the gadget under it, as DoMenu finds it (the last visible one that contains it)
  _pmgUnderCursor = NULL;
  FOREACHINLIST( CMenuGadget, mg_lnNode, pgmCurrentMenu->gm_lhGadgets, itmg) {
    if (itmg->mg_bVisible && FloatBoxToPixBox(pdp, itmg->mg_boxOnScreen)>=PIX2D(pt.x, pt.y)) {
      _pmgUnderCursor = itmg;
    }
  }
  // the focus to that gadget, as the next frame would, and the cursor there
  // for the press (sliders read it). MenuUpdateMouseFocus moves the cursor to
  // SDL's pointer, which is somewhere else only while a later touch waits in
  // the queue: the next frame goes there, as after a mouse move.
  _pixCursorPosI = _pixCursorExternPosI = pt.x;
  _pixCursorPosJ = _pixCursorExternPosJ = pt.y;
  _bMouseUsedLast = !_bEditingString && !_bDefiningKey;
  MenuUpdateMouseFocus();
  _pixCursorPosI = _pixCursorExternPosI = pt.x;
  _pixCursorPosJ = _pixCursorExternPosJ = pt.y;
}

// The app goes to the background, where iOS may end it without a word.
// Options > Controls and an axis's settings keep what is set in them until
// they are left: save it now, as leaving them would. The menu stays up as it
// was.
void MenuKeepSettings(void)
{
  if (!bMenuActive) return;
  if (pgmCurrentMenu==&gmControls) {
    gmControls.ApplyActionSettings();
    ControlsMenuOff();
    ControlsMenuOn();
  } else if (pgmCurrentMenu==&gmCustomizeAxisMenu) {
    gmCustomizeAxisMenu.ApplyActionSettings();  // (and saved: ControlsMenuOff)
    gmCustomizeAxisMenu.ObtainActionSettings(); // (ControlsMenuOn)
  }
}
#endif

static CTimerValue _tvInitialization;
""", "void MenuOnTouchDown(PIX pixI, PIX pixJ)\n{")
    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, "        } else if (msg.message==WM_LBUTTONDOWN || msg.message==WM_LBUTTONDBLCLK) {\n"
           "          MenuOnKeyDown(VK_LBUTTON);\n",
"""        } else if (msg.message==WM_LBUTTONDOWN || msg.message==WM_LBUTTONDBLCLK) {
#ifdef PLATFORM_IOS
          MenuOnTouchDown(LOWORD(msg.lParam), HIWORD(msg.lParam));
#endif
          MenuOnKeyDown(VK_LBUTTON);
""", "          MenuOnTouchDown(LOWORD(msg.lParam), HIWORD(msg.lParam));\n")
    # NETRICSA acts on a press where its pointer was last seen, which the
    # main loop only tells it after the frame's messages
    sub(p, "          ||msg.message==WM_RBUTTONUP) {\n"
           "          if (_pGame->gm_csConsoleState!=CS_ON) {\n"
           "            _pGame->ComputerKeyDown(msg);\n",
"""          ||msg.message==WM_RBUTTONUP) {
          if (_pGame->gm_csConsoleState!=CS_ON) {
#ifdef PLATFORM_IOS
            // a finger: the pointer jumped there with this press (its
            // message says where), which NETRICSA would otherwise only learn
            // after this frame's messages
            if (msg.message==WM_LBUTTONDOWN && _pGame->gm_csComputerState!=CS_OFF && _pGame->gm_csComputerState!=CS_ONINBACKGROUND) {
              _pGame->ComputerMouseMove(LOWORD(msg.lParam), HIWORD(msg.lParam));
            }
#endif
            _pGame->ComputerKeyDown(msg);
""", "_pGame->ComputerMouseMove(LOWORD(msg.lParam), HIWORD(msg.lParam));")
    # No keyboard shows in the menus. A field being typed into (a player's
    # name, a save's description) took no taps at all, so it could not be
    # left: a tap on it now finishes it (Enter: a save gets saved), a tap
    # anywhere else leaves it as it was (Escape).
    p = src / "SeriousSam/Menu.cpp"
    sub(p, "void MenuOnKeyDown( int iVKey)\n{\n\n  // check if mouse buttons used\n",
"""void MenuOnKeyDown( int iVKey)
{
#ifdef PLATFORM_IOS
  // no keyboard shows in the menus: while a field is being typed into (a
  // player's name, a save's description), a tap on it finishes it, as Enter
  // would, and a tap anywhere else leaves it as it was, as Escape would
  // (MenuOnTouchDown has found what is under the finger)
  if (_bEditingString && iVKey==VK_LBUTTON) {
    iVKey = (_pmgUnderCursor!=NULL && _pmgUnderCursor->mg_bFocused) ? VK_RETURN : VK_ESCAPE;
  }
#endif

  // check if mouse buttons used
""", "iVKey = (_pmgUnderCursor!=NULL && _pmgUnderCursor->mg_bFocused) ? VK_RETURN : VK_ESCAPE;")
    # Waiting for a key to bind (Customize controls), the menu takes no
    # messages, and a touch is no button it could bind: the wait never ended
    # without a keyboard or a controller. A tap now ends it, keeping the
    # binding (SDLInput.cpp counts the fingers that come down).
    p = src / "SeriousSam/MenuGadgets.cpp"
    sub(p, "void CMGKeyDefinition::Think( void)\n{\n  if( mg_iState == RELEASE_RETURN_WAITING)\n  {\n",
"""#ifdef PLATFORM_IOS
extern ENGINE_API INDEX inp_ctIOSTouchPresses;
static INDEX _ctIOSTouchPressesAsked = 0;
#endif
void CMGKeyDefinition::Think( void)
{
  if( mg_iState == RELEASE_RETURN_WAITING)
  {
#ifdef PLATFORM_IOS
    _ctIOSTouchPressesAsked = inp_ctIOSTouchPresses;
#endif
""", "_ctIOSTouchPressesAsked = inp_ctIOSTouchPresses;")
    sub(p, """        // refresh all buttons
        pgmCurrentMenu->FillListItems();
        break;
      }
    }
  }
}
""", """        // refresh all buttons
        pgmCurrentMenu->FillListItems();
        break;
      }
    }
#ifdef PLATFORM_IOS
    // a finger tapped (touches can't be bound): stop waiting, keep the binding
    if (mg_iState == PRESS_KEY_WAITING && inp_ctIOSTouchPresses != _ctIOSTouchPressesAsked) {
      mg_iState = DOING_NOTHING;
      _bDefiningKey = FALSE;
      SetBindingNames(/*bDefining=*/FALSE);
    }
#endif
  }
}
""", "inp_ctIOSTouchPresses != _ctIOSTouchPressesAsked")
    # iOS may end the app without a word while it is in the background, so
    # save the settings the game only writes as it quits (CGame::EndInternal)
    # as it goes there: the shell-stored ones, such as Options > Controls'
    # MOUSE ACCELERATION, the audio, video, game and HUD options, and what was
    # set in the console; and the game's own (Data/SeriousSam.gms): the
    # player picked in the menus and the high scores. The players' and
    # controls' are saved as their menus are left; if the app goes away in
    # Options > Controls (or an axis's settings), what is set there is saved
    # as leaving would (MenuKeepSettings).
    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, "        _pNetwork->TogglePause();\n      }\n      IOS_WaitForForeground();\n",
"""        _pNetwork->TogglePause();
      }
      // iOS may end the app from here without a word: keep the settings
      // the game only writes as it quits, or as their menu is left
      MenuKeepSettings();
      _pShell->StorePersistentSymbols(CTString("Scripts\\\\PersistentSymbols.ini"));
      try {
        _pGame->Save_t();
      } catch (const char *strError) {
        CPrintF("Cannot save game settings: %s\\n", strError);
      }
      IOS_WaitForForeground();
""", "_pShell->StorePersistentSymbols(")
    # ...and the touch controls hide first, which stops tilt aiming's motion
    # updates: the loop waits here, so no frame would see the app inactive
    sub(p, """        CPrintF("Cannot save game settings: %s\\n", strError);
      }
      IOS_WaitForForeground();
""", """        CPrintF("Cannot save game settings: %s\\n", strError);
      }
      IOSTouch_Hide();
      IOS_WaitForForeground();
""", "IOSTouch_Hide();\n      IOS_WaitForForeground();")

    # the console's last lines, the clock, the stats and the pause indicators
    # inside the HUD's frame too (the console's lines start at the top left)
    p = src / "GameMP/Game.cpp"
    sub(p, "    // create drawport for messages (left on DH)\n    CDrawPort dpMsg(pdpDrawPort, TRUE);\n",
"""    // create drawport for messages (left on DH)
#ifdef PLATFORM_IOS
    // iOS: inside the screen's rounded corners and above the home indicator, as the HUD
    float afIOSFrame[4];
    IOSTouch_GetHudFrame(afIOSFrame);
    CDrawPort dpMsg(pdpDrawPort, afIOSFrame[0], afIOSFrame[1], afIOSFrame[2]-afIOSFrame[0], afIOSFrame[3]-afIOSFrame[1]);
#else
    CDrawPort dpMsg(pdpDrawPort, TRUE);
#endif
""", "CDrawPort dpMsg(pdpDrawPort, afIOSFrame[0]")

    # A tap on the HUD's messages box marks every message read, as NETRICSA
    # marks the one being read (MarkCurrentRead): the inbox's read flags,
    # which saved games keep (the count is made from them on loading), and
    # the player's count, which the HUD shows (none unread now). NETRICSA
    # makes its list afresh from the flags whenever it opens. As opening
    # NETRICSA does (ComputerPressed), it also drops the new message's
    # "Analyzing..." and the hint and sound still to come, which would
    # otherwise come up for a message already read. Only the touch controls
    # ask for it, in a single-player game (SeriousSam.cpp), on the main thread
    # as NETRICSA.
    p = src / "GameMP/Computer.cpp"
    sub(p, '#include "Render.h"\n',
           '#include "Render.h"\n#ifdef PLATFORM_IOS\n#include "IOSTouch.h"\n#endif\n', '#include "IOSTouch.h"')
    sub(p, "  _ppenPlayer->m_ctUnreadMessages--;\n  _acmMessages[_iActiveMessage].MarkRead();\n}\n",
"""  _ppenPlayer->m_ctUnreadMessages--;
  _acmMessages[_iActiveMessage].MarkRead();
}

#ifdef PLATFORM_IOS
// every message of the first local player read (the touch controls)
extern "C" void IOS_MarkAllMessagesRead(void)
{
  CPlayerSource *ppls = _pGame->gm_lpLocalPlayers[0].lp_pplsPlayerSource;
  if (ppls==NULL) {
    return;
  }
  CPlayer *penPlayer = (CPlayer *)_pNetwork->GetLocalPlayerEntity(ppls);
  if (penPlayer==NULL) {
    return;
  }
  CDynamicStackArray<CCompMessageID> &acmiMsgs = penPlayer->m_acmiMessages;
  for(INDEX i=0; i<acmiMsgs.Count(); i++) {
    acmiMsgs[i].cmi_bRead = TRUE;
  }
  penPlayer->m_ctUnreadMessages = 0;
  penPlayer->m_tmAnalyseEnd = 0;
  penPlayer->m_bPendingMessage = FALSE;
  penPlayer->m_tmMessagePlay = 0;
}
#endif
""", "extern \"C\" void IOS_MarkAllMessagesRead(void)\n{")

    # no touch controls over the loading screen
    p = src / "GameMP/LoadingHook.cpp"
    sub(p, "#include <locale.h>\n",
           '#include <locale.h>\n#ifdef PLATFORM_IOS\n#include "IOSTouch.h"\n#endif\n', '#include "IOSTouch.h"')
    sub(p, "static void LoadingHook_t(CProgressHookInfo *pphi)\n{\n",
"""static void LoadingHook_t(CProgressHookInfo *pphi)
{
#ifdef PLATFORM_IOS
  IOSTouch_Hide();
#endif
""", "  IOSTouch_Hide();\n")

    # the HUD tells the overlay where its score and high score boxes and
    # unread messages box are, how many messages that shows, and what the
    # player holds (sniper rifle, serious bombs)
    p = src / ("EntitiesMP/Common/HUD.cpp" if game == "SamTSE" else "Entities/Common/HUD.cpp")
    sub(p, "// draw border with filter\nstatic void HUD_DrawBorder(",
"""#ifdef PLATFORM_IOS
#include "IOSTouch.h"
// What the touch controls need to know (IOS_GetHudState): where the score
// and high score boxes and the unread messages box are, so they keep their
// buttons clear of them (and a tap or hold on the messages box is its own),
// how many unread messages that box shows and where it is drawn now, and
// what the player holds. Boxes are gathered as HUD_DrawBorder draws them, in
// fractions of the screen.
enum { IOS_HUD_NONE = 0, IOS_HUD_SCORE, IOS_HUD_HISCORE, IOS_HUD_MESSAGES, IOS_HUD_MESSAGESNOW };
static INDEX _iIOSHudPart = IOS_HUD_NONE; // what the borders drawn now belong to
static BOOL _bIOSHudMeasureOnly = FALSE;  // only measure the border, don't draw it
static IOSTouchHud _hudIOS;               // being gathered
static IOSTouchHud _hudIOSDone;           // the last complete one...
static DOUBLE _tmIOSHudDone = -100.0;     // ...and when it was drawn

static void IOS_HudAddBorder(FLOAT fLeft, FLOAT fUp, FLOAT fRight, FLOAT fDown)
{
  if (_iIOSHudPart==IOS_HUD_NONE) return;
  float *af = (_iIOSHudPart==IOS_HUD_SCORE) ? _hudIOS.afScore
            : (_iIOSHudPart==IOS_HUD_HISCORE) ? _hudIOS.afHiScore
            : (_iIOSHudPart==IOS_HUD_MESSAGES) ? _hudIOS.afMessages : _hudIOS.afMessagesNow;
  const FLOAT fW = _pDP->dp_Raster->ra_Width;
  const FLOAT fH = _pDP->dp_Raster->ra_Height;
  const float afBox[4] = { (_pDP->dp_MinI+fLeft)/fW,  (_pDP->dp_MinJ+fUp)/fH,
                           (_pDP->dp_MinI+fRight)/fW, (_pDP->dp_MinJ+fDown)/fH };
  if (af[2]<=af[0]) {
    memcpy(af, afBox, sizeof(afBox));
  } else {
    af[0] = Min(af[0], afBox[0]);
    af[1] = Min(af[1], afBox[1]);
    af[2] = Max(af[2], afBox[2]);
    af[3] = Max(af[3], afBox[3]);
  }
}

extern "C" void IOS_GetHudState(IOSTouchHud *pHud)
{
  *pHud = _hudIOSDone;
  pHud->bValid = (_pTimer->GetHighPrecisionTimer().GetSeconds()-_tmIOSHudDone < 0.5);
}
#endif

// draw border with filter
static void HUD_DrawBorder(""", "static void IOS_HudAddBorder(")
    # the HUD lays itself out inside the frame the overlay gives (the screen
    # less its rounded corners and the home indicator), as if that were the
    # whole screen
    sub(p, "// draw border with filter\nstatic void HUD_DrawBorder(",
"""#ifdef PLATFORM_IOS
// A drawport for the frame IOSTouch_GetHudFrame gives -- the screen less its
// rounded corners and the home indicator -- that DrawHUD draws into while
// this is in scope, as if it were the whole screen. It only moves the HUD:
// nothing is cut off at the frame's edges. Back on the drawport DrawHUD was
// given when it goes out of scope. No frame (a screen with square corners
// and no home indicator): no change.
static PIXaabbox2D IOS_HudFrameBox(CDrawPort *pdp)
{
  float af[4];
  IOSTouch_GetHudFrame(af);
  const PIX pixRW = pdp->dp_Raster->ra_Width;
  const PIX pixRH = pdp->dp_Raster->ra_Height;
  const PIX pixL = Clamp((PIX)ceil( af[0]*pixRW)-pdp->dp_MinI, (PIX)0,    (PIX)pdp->GetWidth());
  const PIX pixT = Clamp((PIX)ceil( af[1]*pixRH)-pdp->dp_MinJ, (PIX)0,    (PIX)pdp->GetHeight());
  const PIX pixR = Clamp((PIX)floor(af[2]*pixRW)-pdp->dp_MinI, pixL+1, (PIX)pdp->GetWidth());
  const PIX pixB = Clamp((PIX)floor(af[3]*pixRH)-pdp->dp_MinJ, pixT+1, (PIX)pdp->GetHeight());
  return PIXaabbox2D(PIX2D(pixL, pixT), PIX2D(pixR, pixB));
}

class CIOSHudFrame {
public:
  CDrawPort *ihf_pdpWhole;
  CDrawPort ihf_dpFrame;
  BOOL ihf_bOn;
  CIOSHudFrame(CDrawPort *pdp) : ihf_pdpWhole(pdp), ihf_dpFrame(pdp, IOS_HudFrameBox(pdp)), ihf_bOn(FALSE)
  {
    if (ihf_dpFrame.GetWidth()==pdp->GetWidth() && ihf_dpFrame.GetHeight()==pdp->GetHeight()) return;
    // clipped as the whole drawport is
    ihf_dpFrame.dp_ScissorMinI = pdp->dp_ScissorMinI;
    ihf_dpFrame.dp_ScissorMinJ = pdp->dp_ScissorMinJ;
    ihf_dpFrame.dp_ScissorMaxI = pdp->dp_ScissorMaxI;
    ihf_dpFrame.dp_ScissorMaxJ = pdp->dp_ScissorMaxJ;
    pdp->Unlock();
    ihf_bOn = ihf_dpFrame.Lock();
    if (!ihf_bOn) pdp->Lock();
  }
  ~CIOSHudFrame()
  {
    if (!ihf_bOn) return;
    ihf_dpFrame.Unlock();
    ihf_pdpWhole->Lock();
    _pDP = ihf_pdpWhole;
  }
};
#endif

// draw border with filter
static void HUD_DrawBorder(""", "class CIOSHudFrame {")
    sub(p, "  // prepare font and text dimensions\n  CTString strValue;\n",
"""#ifdef PLATFORM_IOS
  // the rest inside the screen's rounded corners and above the home indicator
  // (the Second Encounter's sniper mask, above, still covers the whole screen)
  CIOSHudFrame ihf(pdpCurrent);
  if (ihf.ihf_bOn) {
    _pDP = &ihf.ihf_dpFrame;
    _pixDPWidth  = _pDP->GetWidth();
    _pixDPHeight = _pDP->GetHeight();
    _fResolutionScaling  = (FLOAT)_pixDPWidth /640.0f;
    _fResolutionScalingY = (FLOAT)_pixDPHeight/480.0f;
  }
#endif
  // prepare font and text dimensions
  CTString strValue;
""", "CIOSHudFrame ihf(pdpCurrent);")
    sub(p, "  const FLOAT fDown  = fCenterJ  + fSizeJ/2 +1;\n",
"""  const FLOAT fDown  = fCenterJ  + fSizeJ/2 +1;
#ifdef PLATFORM_IOS
  IOS_HudAddBorder(fLeft, fUp, fRight, fDown);
  if (_bIOSHudMeasureOnly) return;
#endif
""", "  IOS_HudAddBorder(fLeft, fUp, fRight, fDown);\n")
    sub(p, "  _penWeapons = (CPlayerWeapons*)&*_penPlayer->m_penWeapons;\n",
"""  _penWeapons = (CPlayerWeapons*)&*_penPlayer->m_penWeapons;
#ifdef PLATFORM_IOS
  memset(&_hudIOS, 0, sizeof(_hudIOS));
#endif
""", "  memset(&_hudIOS, 0, sizeof(_hudIOS));\n")
    sub(p, "    // prepare and draw score or frags info \n",
           "#ifdef PLATFORM_IOS\n    _iIOSHudPart = IOS_HUD_SCORE;\n#endif\n    // prepare and draw score or frags info \n",
        "    _iIOSHudPart = IOS_HUD_SCORE;\n")
    sub(p, "  // eventually draw mana info \n",
           "#ifdef PLATFORM_IOS\n  _iIOSHudPart = IOS_HUD_NONE;\n#endif\n  // eventually draw mana info \n",
        "  _iIOSHudPart = IOS_HUD_NONE;\n#endif\n  // eventually draw mana info")
    # the high score box (its part ends where the messages box is measured,
    # just below)
    sub(p, "    // prepare and draw hiscore info \n",
           "#ifdef PLATFORM_IOS\n    _iIOSHudPart = IOS_HUD_HISCORE;\n#endif\n    // prepare and draw hiscore info \n",
        "    _iIOSHudPart = IOS_HUD_HISCORE;\n")
    # the unread messages box goes in the top row, right of the high score box:
    # on PC it sits at the bottom right, under the touch controls' FIRE (the
    # legacy HUD's top right is under MENU). Measured where it sits when it
    # shows (it only shows while there are unread messages); a new message
    # drops it down from there and back, as it slid in on PC. It still blinks.
    sub(p, "    // prepare and draw unread messages\n",
"""#ifdef PLATFORM_IOS
    const FLOAT fRowIOSMsg = pixTopBound+fHalfUnit;
    const FLOAT fColIOSMsg = 320.0f-fOneUnit+fAdvUnit+fHalfUnit+fChrUnit*4;
    {
      const FLOAT fAdvM = fAdvUnit+fChrUnit*4/2-fHalfUnit;
      _iIOSHudPart = IOS_HUD_MESSAGES;
      _bIOSHudMeasureOnly = TRUE;
      HUD_DrawBorder( fColIOSMsg,       fRowIOSMsg, fOneUnit,   fOneUnit, colBorder);
      HUD_DrawBorder( fColIOSMsg+fAdvM, fRowIOSMsg, fChrUnit*4, fOneUnit, colBorder);
      _bIOSHudMeasureOnly = FALSE;
      _iIOSHudPart = IOS_HUD_NONE;
    }
#endif
    // prepare and draw unread messages
""", "_iIOSHudPart = IOS_HUD_MESSAGES;")
    sub(p, "      fCol = pixRightBound-fHalfUnit-fAdvUnit-fChrUnit*4;\n      const FLOAT tmIn = 0.5f;\n",
"""      fCol = pixRightBound-fHalfUnit-fAdvUnit-fChrUnit*4;
#ifdef PLATFORM_IOS
      fRow = fRowIOSMsg;
      fCol = fColIOSMsg;
      _hudIOS.bMessages = TRUE;  // drawn: a tap or hold on it is the box's
      _hudIOS.ctMessages = _penPlayer->m_ctUnreadMessages;
#endif
      const FLOAT tmIn = 0.5f;
""", "_hudIOS.bMessages = TRUE;  // drawn: a tap or hold")
    sub(p, "        fCol-=fAdvUnit*15*fRatio;\n",
"""        fCol-=fAdvUnit*15*fRatio;
#ifdef PLATFORM_IOS
        fRow = fRowIOSMsg+fAdvUnit*5*fRatio;
        fCol = fColIOSMsg;
#endif
""", "fRow = fRowIOSMsg+fAdvUnit*5*fRatio;")
    # and where the box is drawn this frame: a new message drops it down a
    # little for a while, and a tap there is the box's too
    sub(p, """      fAdv = fAdvUnit+ fChrUnit*4/2 -fHalfUnit;
      HUD_DrawBorder( fCol,      fRow, fOneUnit,   fOneUnit, col);
      HUD_DrawBorder( fCol+fAdv, fRow, fChrUnit*4, fOneUnit, col);
""", """      fAdv = fAdvUnit+ fChrUnit*4/2 -fHalfUnit;
#ifdef PLATFORM_IOS
      _iIOSHudPart = IOS_HUD_MESSAGESNOW;
#endif
      HUD_DrawBorder( fCol,      fRow, fOneUnit,   fOneUnit, col);
      HUD_DrawBorder( fCol+fAdv, fRow, fChrUnit*4, fOneUnit, col);
#ifdef PLATFORM_IOS
      _iIOSHudPart = IOS_HUD_NONE;
#endif
""", "      _iIOSHudPart = IOS_HUD_MESSAGESNOW;\n")
    # With nothing unread the box stays on iOS, dim and still where it sits,
    # in a single-player game (on PC it goes away): holding it is the touch
    # controls' way into NETRICSA (their USE never opens it; IOSTouch.h), and
    # a tap on it marks the messages read without taking that away
    sub(p, """      HUD_DrawIcon(   fCol,      fRow, _toMessage, %s, 0.0f, TRUE);
    }
""" % ("C_WHITE /*col*/" if game == "SamTSE" else "col"),
"""      HUD_DrawIcon(   fCol,      fRow, _toMessage, %s, 0.0f, TRUE);
    }
#ifdef PLATFORM_IOS
    else if( hud_bShowMessages && bSinglePlay) {
      const FLOAT fAdvM = fAdvUnit+fChrUnit*4/2-fHalfUnit;
      const ULONG ulAlphaHUD = _ulAlphaHUD;
      _ulAlphaHUD = ulAlphaHUD/2;
      _hudIOS.bMessages = TRUE;  // drawn: a hold on it opens NETRICSA
      _hudIOS.ctMessages = 0;
      _iIOSHudPart = IOS_HUD_MESSAGESNOW;
      HUD_DrawBorder( fColIOSMsg,       fRowIOSMsg, fOneUnit,   fOneUnit, _colHUD);
      HUD_DrawBorder( fColIOSMsg+fAdvM, fRowIOSMsg, fChrUnit*4, fOneUnit, _colHUD);
      _iIOSHudPart = IOS_HUD_NONE;
      strValue = "0";
      HUD_DrawText(   fColIOSMsg+fAdvM, fRowIOSMsg, strValue, _colHUD, 1.0f);
      HUD_DrawIcon(   fColIOSMsg,       fRowIOSMsg, _toMessage, %s, 0.0f, FALSE);
      _ulAlphaHUD = ulAlphaHUD;
    }
#endif
""" % (("C_WHITE /*col*/", "C_WHITE") if game == "SamTSE" else ("col", "_colHUD")), "_hudIOS.bMessages = TRUE;  // drawn: a hold on it opens NETRICSA")
    # No row of small ammo boxes at the bottom right (one per ammo type, with
    # a bar, and the Second Encounter's serious bomb box): on the phone it
    # only took the corner FIRE wants. The current weapon's ammo still shows
    # at the bottom middle, and the touch controls' BOMB says how many bombs
    # there are. (FillWeaponAmmoTables still runs: it keeps the ammo tables'
    # changes, which the HUD shakes boxes for, up to date.) In the Second
    # Encounter this goes on over the PC's power-ups, which are in the top
    # row on iOS (below).
    sub(p, "  FillWeaponAmmoTables();\n",
"""  FillWeaponAmmoTables();
#ifndef PLATFORM_IOS  // (iOS: no ammo row, see IOSTouch.h%s)
""" % (", nor the power-ups here" if game == "SamTSE" else ""), "#ifndef PLATFORM_IOS  // (iOS: no ammo row")
    if game == "SamTFE":
        sub(p, "      fCol -= fAdvUnitS;\n    }\n  }\n\n#define TXT_WIDTH_SCORE",
               "      fCol -= fAdvUnitS;\n    }\n  }\n#endif // PLATFORM_IOS\n\n#define TXT_WIDTH_SCORE",
            "  }\n#endif // PLATFORM_IOS\n\n#define TXT_WIDTH_SCORE")
    # The Second Encounter's power-ups go in the top row, in the gap between
    # the score and the high score: above the ammo row at the bottom right,
    # as on PC, they sat under the touch controls' FIRE (and ZOOM), and they
    # blink, and beep, as they run out. Drawn once the top row's sizes are
    # known; the same boxes, icons, bars and sound as on PC, left to right.
    if game == "SamTSE":
        sub(p, "  // draw powerup(s) if needed\n",
               "  // draw powerup(s) if needed (iOS: in the top row, below)\n", "(iOS: in the top row, below)")
        sub(p, "    fCol -= fAdvUnitS;\n  }\n\n#define TXT_WIDTH_SCORE",
               "    fCol -= fAdvUnitS;\n  }\n#endif // PLATFORM_IOS\n\n#define TXT_WIDTH_SCORE",
            "  }\n#endif // PLATFORM_IOS\n\n#define TXT_WIDTH_SCORE")
        sub(p, "  fNextUnit *= fUpperSize;\n\n  // draw oxygen info if needed\n",
"""  fNextUnit *= fUpperSize;

#ifdef PLATFORM_IOS
  // the power-ups, in the top row between the score and the high score (on
  // PC they are above the ammo row, where the touch controls' FIRE is):
  // room for all four, centred in the gap, smaller if the gap is narrow (a
  // larger HUD), left to right
  {
    PrepareColorTransitions( colMax, colTop, colMid, C_RED, 0.66f, 0.33f, FALSE);
    TIME *ptmPowerups = (TIME*)&_penPlayer->m_tmInvisibility;
    TIME *ptmPowerupsMax = (TIME*)&_penPlayer->m_tmInvisibilityMax;
    const FLOAT fGapL = pixLeftBound+fAdvUnit+fChrUnit*8;          // the score's value box ends
    const FLOAT fGapR = 320.0f-fOneUnit-fChrUnit*4-fHalfUnit;      // the high score's icon begins
    const FLOAT fSize = Clamp((fGapR-fGapL-fHalfUnit)/(3*fAdvUnit+fOneUnit), 0.5f, 1.0f);
    const FLOAT fOneP = fOneUnit*fSize;
    const FLOAT fAdvP = fAdvUnit*fSize;
    const FLOAT fScaling = _fCustomScaling;
    fRow = pixTopBound+fHalfUnit;
    fCol = (fGapL+fGapR-3*fAdvP)*0.5f;
    for( i=0; i<MAX_POWERUPS; i++)
    {
      // skip if not active
      const TIME tmDelta = ptmPowerups[i] - _tmNow;
      if( tmDelta<=0) continue;
      fNormValue = tmDelta / ptmPowerupsMax[i];
      // draw icon and a little bar (in the box as on PC)
      _fCustomScalingAdjustment = 1.0f;
      HUD_DrawBorder( fCol, fRow, fOneP, fOneP, colBorder);
      _fCustomScaling = fScaling*fSize;
      _fCustomScalingAdjustment = 0.5f/0.7f;
      HUD_DrawIcon(   fCol,              fRow, _atoPowerups[i], C_WHITE /*_colHUD*/, fNormValue, TRUE);
      HUD_DrawBar(    fCol+fOneP*0.5f,   fRow, (INDEX) (fOneP/5), (INDEX) (fOneP-2), BO_DOWN, NONE, fNormValue);
      _fCustomScaling = fScaling;
      _fCustomScalingAdjustment = 1.0f;
      // play sound if icon is flashing
      if(fNormValue<=(_cttHUD.ctt_fLowMedium/2)) {
        // activate blinking only if value is <= half the low edge
        INDEX iLastTime = (INDEX)(_tmLast*4);
        INDEX iCurrentTime = (INDEX)(_tmNow*4);
        if(iCurrentTime&1 & !(iLastTime&1)) {
          ((CPlayer *)penPlayerCurrent)->PlayPowerUpSound();
        }
      }
      // advance to next position
      fCol += fAdvP;
    }
  }
#endif

  // draw oxygen info if needed
""", "the power-ups, in the top row between the score and the high score")
    if game == "SamTSE":
        strHolds ="""  _hudIOS.bSniper = (_penWeapons->m_iCurrentWeapon==WEAPON_SNIPER);
  _hudIOS.ctBombs = _penPlayer->m_iSeriousBombCount;
"""
    else:
        strHolds = "  // (no sniper rifle or serious bombs in the First Encounter)\n"
    sub(p, "  // draw cheat modes\n",
"""#ifdef PLATFORM_IOS
  // done: for the touch controls
""" + strHolds + """  _hudIOSDone = _hudIOS;
  _tmIOSHudDone = _pTimer->GetHighPrecisionTimer().GetSeconds();
#endif

  // draw cheat modes
""", "  _hudIOSDone = _hudIOS;\n")

    # ------------------------------------------------- the weapon wheel
    # NEXT WPN and PREV WPN, slid or held, open the touch controls' weapon
    # wheel (ios/IOSTouch.m): one slice per weapon, with the HUD's icons and
    # counts. The HUD tells it what the player has, every frame (not only
    # while the HUD draws), and hands it each weapon's icon from the game's
    # data once, between frames.
    p = src / ("EntitiesMP/Common/HUD.cpp" if game == "SamTSE" else "Entities/Common/HUD.cpp")
    sub(p, """extern "C" void IOS_GetHudState(IOSTouchHud *pHud)
{
  *pHud = _hudIOSDone;
  pHud->bValid = (_pTimer->GetHighPrecisionTimer().GetSeconds()-_tmIOSHudDone < 0.5);
}
#endif
""", """extern "C" void IOS_GetHudState(IOSTouchHud *pHud)
{
  *pHud = _hudIOSDone;
  pHud->bValid = (_pTimer->GetHighPrecisionTimer().GetSeconds()-_tmIOSHudDone < 0.5);
}

// The weapon wheel's view of the first player's weapons (every frame, main
// thread, whether or not the HUD draws): owned, what the game would switch to
// (owned and HasAmmo: what SelectWeaponChange accepts -- the double shotgun
// needs two shells), the HUD's own counts, and whether a pick would be taken
// now (alive, no cutscene camera, not walked by an action marker: otherwise
// the player's actions never reach the weapons)
static void FillWeaponAmmoTables(void);
extern "C" void IOS_GetWeapons(IOSTouchWeapons *pw)
{
  memset(pw, 0, sizeof(*pw));
  pw->iMap = %(MAP)s;
  CPlayer *pl = (CPlayer *)CEntity::GetPlayerEntity(0);
  if (pl==NULL || pl->m_penWeapons==NULL) return;
  CPlayerWeapons *penOld = _penWeapons;
  _penWeapons = (CPlayerWeapons *)&*pl->m_penWeapons;
  FillWeaponAmmoTables();  // the HUD's own counts (DrawHUD fills them again every frame anyway)
  pw->bValid = TRUE;
  pw->bCanSelect = (pl->GetFlags()&ENF_ALIVE) && pl->m_penCamera==NULL && pl->m_penActionMarker==NULL;
  pw->iWanted = _penWeapons->m_iWantedWeapon;
  pw->bInfiniteAmmo = GetSP()->sp_bInfiniteAmmo;
  for (INDEX w=1; w<IOSTOUCH_WPN_MAX && w<18; w++) {
    pw->aiAmmo[w] = pw->aiMaxAmmo[w] = -1;
    if (_awiWeapons[w].wi_wtWeapon==WEAPON_NONE) continue;
    const BOOL bOwned = (_penWeapons->m_iAvailableWeapons&(1<<(w-1)))!=0;
    if (bOwned) pw->ulOwned |= 1u<<w;
    if (bOwned && _penWeapons->HasAmmo((WeaponType)w)) pw->ulReady |= 1u<<w;
    if (_awiWeapons[w].wi_paiAmmo!=NULL) {
      pw->aiAmmo[w] = _awiWeapons[w].wi_paiAmmo->ai_iAmmoAmmount;
      pw->aiMaxAmmo[w] = _awiWeapons[w].wi_paiAmmo->ai_iMaxAmmoAmmount;
    }
  }
  _penWeapons = penOld;
}

// A weapon's HUD icon for the weapon wheel: its texture's first frame (R G B
// A, not premultiplied). Uploading it freed the texels (it isn't TEX_STATIC):
// they are loaded again from the game's data and kept. Main thread, between
// frames (the main loop asks), never inside a touch callback. The two colts'
// is the colt's.
extern "C" int IOS_GetWeaponIcon(int iWeapon, unsigned char *pubRGBA, int ctMaxBytes, int *piWidth, int *piHeight)
{
  if (iWeapon<1 || iWeapon>=18 || _awiWeapons[iWeapon].wi_ptoWeapon==NULL) return 0;
  CTextureData *ptd = (CTextureData *)_awiWeapons[iWeapon].wi_ptoWeapon->GetData();
  if (ptd==NULL) return 0;                               // InitHUD hasn't run yet
  if (ptd->td_pulFrames==NULL) ptd->Force(TEX_STATIC);   // reloads it, and keeps it from now on
  if (ptd->td_pulFrames==NULL) return 0;
  const PIX pixW = ptd->GetPixWidth(), pixH = ptd->GetPixHeight();
  if (pixW<=0 || pixH<=0 || pixW*pixH*4>ctMaxBytes) return 0;
  memcpy(pubRGBA, ptd->td_pulFrames, pixW*pixH*4);
  *piWidth = pixW;
  *piHeight = pixH;
  return 1;
}
#endif
""" % {"MAP": "IOSTOUCH_WHEEL_TSE" if game == "SamTSE" else "IOSTOUCH_WHEEL_TFE"}, "extern \"C\" void IOS_GetWeapons(IOSTouchWeapons *pw)")
    # While the wheel is open the game holds still, so the HUD's weapon row
    # (up for a while after a weapon change) would stand frozen in the
    # wheel's cancel gap: not drawn then. It comes up for its time after a pick.
    sub(p, "  if( (_tmNow - _penWeapons->m_tmWeaponChangeRequired) < hud_tmWeaponsOnScreen) {\n",
"""#ifdef PLATFORM_IOS
  if( (_tmNow - _penWeapons->m_tmWeaponChangeRequired) < hud_tmWeaponsOnScreen && !IOSTouch_HoldsGame()) {
#else
  if( (_tmNow - _penWeapons->m_tmWeaponChangeRequired) < hud_tmWeaponsOnScreen) {
#endif
""", "hud_tmWeaponsOnScreen && !IOSTouch_HoldsGame()) {")

    # The wheel's pick reaches the weapons as the player action's select-weapon
    # field, a value no key sends (8 or 9 weapon keys): IOS_SELECT_WEAPON_DIRECT
    # - 1 + the weapon's number, that very weapon -- a key names a group, and
    # which of its two it gives depends on the weapon in hand. The game's own
    # test (owned and HasAmmo) then takes it or not. In all three weapon
    # files: CMake copies PlayerWeapons_old.es (or HD) over PlayerWeapons.es at
    # configure time. ECC takes no preprocessor lines in function bodies, so
    # the desktop keeps a branch no value reaches.
    en = "EntitiesMP" if game == "SamTSE" else "Entities"
    for f in ("PlayerWeapons.es", "PlayerWeapons_old.es", "PlayerWeaponsHD.es"):
        p = src / en / f
        sub(p, "#define MAX_WEAPONS 30\n",
"""#define MAX_WEAPONS 30
#ifdef PLATFORM_IOS
// the iOS touch controls' weapon wheel: one weapon by its number, as IOS_SELECT_WEAPON_DIRECT-1+weapon in the
// select-weapon field (GameMP/Game.cpp); no weapon key sends 16 or more
#define IOS_SELECT_WEAPON_DIRECT 16
#else
#define IOS_SELECT_WEAPON_DIRECT 0x7FFFFFFF
#endif
""", "#define IOS_SELECT_WEAPON_DIRECT 16")
        sub(p, "\n    // if selecting directly\n    } else {",
"""
    // iOS weapon wheel: one weapon by its number
    } else if (iSelect>=IOS_SELECT_WEAPON_DIRECT) {
      EwtTemp = (WeaponType)(iSelect-IOS_SELECT_WEAPON_DIRECT+1);

    // if selecting directly
    } else {""", "} else if (iSelect>=IOS_SELECT_WEAPON_DIRECT) {")
    assert (src / en / "PlayerWeapons.es").read_bytes() == (src / en / "PlayerWeapons_old.es").read_bytes(), \
        game + ": PlayerWeapons.es and PlayerWeapons_old.es differ (CMake copies the one over the other)"

    p = src / "GameMP/Game.cpp"
    sub(p, "#define IOS_PLACT_COMPUTER    (1L<<6)\n",
"""#define IOS_PLACT_COMPUTER    (1L<<6)
// the select-weapon field (Player.es PLACT_SELECT_WEAPON_*: bits 14-18, the
// First Encounter's 9-13), and the value that names one weapon
// (PlayerWeapons.es)
#ifdef FIRST_ENCOUNTER
#define IOS_PLACT_SELECT_WEAPON_SHIFT 9
#else
#define IOS_PLACT_SELECT_WEAPON_SHIFT 14
#endif
#define IOS_PLACT_SELECT_WEAPON_MASK  (0x1FL<<IOS_PLACT_SELECT_WEAPON_SHIFT)
#define IOS_SELECT_WEAPON_DIRECT      16
""", "#define IOS_PLACT_SELECT_WEAPON_SHIFT 9")
    sub(p, "    paAction.pa_ulButtons |= IOS_TouchButtonActions(tiTouch.ulButtons);\n",
"""    paAction.pa_ulButtons |= IOS_TouchButtonActions(tiTouch.ulButtons);
    // the weapon wheel's pick: that weapon, in the select field (a number, so
    // it replaces a weapon key's value in this tick)
    if (tiTouch.iSelectWeapon>=1 && tiTouch.iSelectWeapon<=16) {
      paAction.pa_ulButtons = (paAction.pa_ulButtons&~IOS_PLACT_SELECT_WEAPON_MASK)
                            | ((ULONG)(IOS_SELECT_WEAPON_DIRECT-1+tiTouch.iSelectWeapon)<<IOS_PLACT_SELECT_WEAPON_SHIFT);
    }
""", "tiTouch.iSelectWeapon>=1 && tiTouch.iSelectWeapon<=16")
    # the wheel holds the game with the local pause, but isn't a pause: no "Paused"
    sub(p, "      } else if (_pNetwork->IsPaused() || _pNetwork->GetLocalPause()) {\n",
"""#ifdef PLATFORM_IOS
      } else if (_pNetwork->IsPaused() || (_pNetwork->GetLocalPause() && !IOSTouch_HoldsGame())) {
#else
      } else if (_pNetwork->IsPaused() || _pNetwork->GetLocalPause()) {
#endif
""", "(_pNetwork->GetLocalPause() && !IOSTouch_HoldsGame())")

    p = src / "SeriousSam/SeriousSam.cpp"
    # every frame, before the overlay's update: what the player has, and the
    # icons the wheel still lacks (at most once a second each), here between
    # frames -- the reload reads the game's data and touches GL
    sub(p, "  IOSTouchHud hud;\n  IOS_GetHudState(&hud);\n",
"""  IOSTouchHud hud;
  IOS_GetHudState(&hud);
  // the weapon wheel: what the player has, and the HUD's icons it still lacks
  IOSTouchWeapons wpn;
  IOS_GetWeapons(&wpn);
  IOSTouch_SetWeapons(&wpn);
  if (iMode==IOSTOUCH_GAMEPLAY) {
    static unsigned char aubIcon[64*64*4];
    const unsigned int ulWant = IOSTouch_WantedIcons(_pTimer->GetHighPrecisionTimer().GetSeconds());
    for (int w=1; w<IOSTOUCH_WPN_MAX; w++) {
      if (!(ulWant&(1u<<w))) continue;
      int iW = 0, iH = 0;
      if (IOS_GetWeaponIcon(w, aubIcon, sizeof(aubIcon), &iW, &iH)) IOSTouch_SetWeaponIcon(w, aubIcon, iW, iH);
    }
  }
""", "IOSTouch_SetWeapons(&wpn);")
    # the open wheel holds a single-player game, as the menu and the console do
    sub(p, "                       _pGame->gm_csComputerState==CS_ON || _pGame->gm_csComputerState==CS_TURNINGON || _pGame->gm_csComputerState==CS_TURNINGOFF);\n",
"""#ifdef PLATFORM_IOS
                       _pGame->gm_csComputerState==CS_ON || _pGame->gm_csComputerState==CS_TURNINGON || _pGame->gm_csComputerState==CS_TURNINGOFF
                       || IOSTouch_HoldsGame());  // the touch controls' weapon wheel is open
#else
                       _pGame->gm_csComputerState==CS_ON || _pGame->gm_csComputerState==CS_TURNINGON || _pGame->gm_csComputerState==CS_TURNINGOFF);
#endif
""", "|| IOSTouch_HoldsGame());  // the touch controls' weapon wheel is open")

    # ------------------------------------------------------------ CAMERA
    # The touch controls' CAMERA (ios/IOSCapture.c) reads back the frame at
    # two points: once the view and the first-person weapon are drawn, before
    # the crosshair and the HUD (the clean photo), and once all of it is,
    # before the swap (the HUD one). Also built by the Linux test rig
    # (IOS_CAMERA_RIG), which drives the same code.
    p = src / "Engine/Graphics/DrawPort.cpp"
    sub(p, "void CDrawPort::GrabScreen( class CImageInfo &iiGrabbedImage, INDEX iGrabZBuffer/*=0*/) const\n",
"""#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
// The touch controls' CAMERA: the w x h frame drawn so far, as RGBA (the
// bottom row first). 1 if it could.
extern "C" int IOS_ReadFrameRGBA(int w, int h, unsigned char *p)
{
  if (_pGfx->gl_eCurrentAPI!=GAT_OGL || w<=0 || h<=0) return 0;
  while (pglGetError()!=GL_NO_ERROR) {}  // (not ours)
  pglPixelStorei(GL_PACK_ALIGNMENT, 4);
  pglReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, (GLvoid*)p);
  return pglGetError()==GL_NO_ERROR;
}
#endif

void CDrawPort::GrabScreen( class CImageInfo &iiGrabbedImage, INDEX iGrabZBuffer/*=0*/) const
""", "IOS_ReadFrameRGBA")

    # A selfie's flash: while CAMERA's photo view is drawn, it may light each
    # model further (ios/IOSPhotoCam.cpp sets the hook only then), after the
    # model's own lights and its entity's adjustments
    p = src / "Engine/Rendering/RenderModels.cpp"
    sub(p, "extern INDEX mdl_iShadowQuality;\n",
"""extern INDEX mdl_iShadowQuality;
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
// (the touch controls' CAMERA: a selfie's flash, NULL but while it is drawn)
ENGINE_API void (*_pfnIOSFlash)(CEntity *pen, const FLOAT3D &vModel, FLOAT3D &vLightDirection, COLOR &colLight, COLOR &colAmbient) = NULL;
#endif
""", "_pfnIOSFlash)(CEntity *pen")
    sub(p, """  const BOOL bAllowShadows = en.AdjustShadingParameters( vTotalLightDirection, colLight, colAmbient);
  bRenderModelShadow = (bRenderModelShadow && bAllowShadows && bRenderShadow && mdl_iShadowQuality>0);
  
  // prepare render model structure
""", """  const BOOL bAllowShadows = en.AdjustShadingParameters( vTotalLightDirection, colLight, colAmbient);
  bRenderModelShadow = (bRenderModelShadow && bAllowShadows && bRenderShadow && mdl_iShadowQuality>0);
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  if (_pfnIOSFlash!=NULL) _pfnIOSFlash(&en, plModel.pl_PositionVector, vTotalLightDirection, colLight, colAmbient);
#endif
  
  // prepare render model structure
""", "_pfnIOSFlash(&en, plModel.pl_PositionVector, vTotalLightDirection, colLight, colAmbient);\n#endif\n  \n  // prepare render model")
    sub(p, """  const BOOL bAllowShadows = en.AdjustShadingParameters( vTotalLightDirection, colLight, colAmbient);
  bRenderModelShadow = (bRenderModelShadow && bAllowShadows && bRenderShadow && mdl_iShadowQuality>0);

  ULONG &ulRenFlags = RM_GetRenderFlags();
""", """  const BOOL bAllowShadows = en.AdjustShadingParameters( vTotalLightDirection, colLight, colAmbient);
  bRenderModelShadow = (bRenderModelShadow && bAllowShadows && bRenderShadow && mdl_iShadowQuality>0);
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  if (_pfnIOSFlash!=NULL) _pfnIOSFlash(&en, plModel.pl_PositionVector, vTotalLightDirection, colLight, colAmbient);
#endif

  ULONG &ulRenFlags = RM_GetRenderFlags();
""", "_pfnIOSFlash(&en, plModel.pl_PositionVector, vTotalLightDirection, colLight, colAmbient);\n#endif\n\n  ULONG &ulRenFlags")

    # (ECC takes no preprocessor lines in function bodies: a macro)
    p = src / ("EntitiesMP/Player.es" if game == "SamTSE" else "Entities/Player.es")
    sub(p, "#define STR_READ_MESSAGE_HINT \"Press USE to read the message!\"\n#define READ_MESSAGE_HINT_AND\n#endif\n",
"""#define STR_READ_MESSAGE_HINT "Press USE to read the message!"
#define READ_MESSAGE_HINT_AND
#endif
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
// the touch controls' CAMERA takes its clean photo here (ios/IOSCapture.c)
extern "C" void IOSCapture_AfterScene(void);
#define IOS_CAPTURE_AFTER_SCENE() IOSCapture_AfterScene()
#else
#define IOS_CAPTURE_AFTER_SCENE()
#endif
""", "IOS_CAPTURE_AFTER_SCENE() IOSCapture_AfterScene()")
    sub(p, "    // render crosshair",
"""    // (the touch controls' CAMERA: its clean photo, the view and the weapon but no crosshair or HUD)
    IOS_CAPTURE_AFTER_SCENE();

    // render crosshair""", "    IOS_CAPTURE_AFTER_SCENE();\n")

    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, "#include <sys/stat.h>\n#include <Engine/CurrentVersion.h>\n",
"""#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
#include "IOSCapture.h"
#endif
#include <sys/stat.h>
#include <Engine/CurrentVersion.h>
""", '#include "IOSCapture.h"')
    sub(p, "  // redraw the view\n  if( !IsIconic(_hwndMain) && pdp!=NULL && pdp->Lock())\n  {\n",
"""  // redraw the view
  if( !IsIconic(_hwndMain) && pdp!=NULL && pdp->Lock())
  {
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
    // the touch controls' CAMERA reads back this frame (IOSCapture.c)
    IOSCapture_FrameBegin(pdp->dp_Raster->ra_Width, pdp->dp_Raster->ra_Height);
#endif
""", "IOSCapture_FrameBegin(")
    sub(p, "    // show\n    pvpViewPort->SwapBuffers();\n",
"""#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
    IOSCapture_AfterHud();  // (CAMERA's photo with the HUD)
#endif
    // show
    pvpViewPort->SwapBuffers();
""", "IOSCapture_AfterHud();")

    # CAMERA's own view (ios/IOSPhotoCam.cpp): a selfie, Action Freeze and the
    # cinematic burst draw the game from a camera of their own, with no HUD
    # and nothing else over it
    p = src / "GameMP/Game.cpp"
    sub(p, '#include "GameMP/Game.h"\n',
"""#include "GameMP/Game.h"
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
#include "IOSPhotoCam.h"
#endif
""", '#include "IOSPhotoCam.h"')
    sub(p, "    BOOL bHadViewers = FALSE;\n",
"""    BOOL bHadViewers = FALSE;
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
    // (the touch controls' CAMERA's view: no HUD, no messages over it)
    const BOOL bIOSPhotoView = IOSPhotoCam_IsActive();
    if (bIOSPhotoView) ulFlags &= ~GRV_SHOWEXTRAS;
#endif
""", "const BOOL bIOSPhotoView = IOSPhotoCam_IsActive();")
    sub(p, "          if (!CAM_IsOn()) {\n",
"""#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
          if (bIOSPhotoView && IOSPhotoCam_Render(apenViewers[i], pdp)) {
            // drawn from CAMERA's camera (a selfie, Action Freeze)
          } else
#endif
          if (!CAM_IsOn()) {
""", "IOSPhotoCam_Render(apenViewers[i], pdp)")

    # (a quick save or load from a keyboard's F6/F9 while CAMERA holds the
    # game: ignored, so no posed or frozen view is ever saved, and nothing it
    # still points at is cleared away under it)
    sub(p, "void CGame::GameMainLoop(void)\n{\n",
"""void CGame::GameMainLoop(void)
{
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  if (IOSPhotoCam_IsActive()) {
    gam_bQuickSave = FALSE;
    gam_bQuickLoad = FALSE;
  }
#endif
""", "  if (IOSPhotoCam_IsActive()) {\n    gam_bQuickSave = FALSE;")

    # ---------------------------------------------------- multiplayer: LAN
    # SEARCH LAN looked only on this computer (its own addresses). A phone
    # asks every address on its Wi-Fi in turn instead (iOS sends no
    # broadcasts without an entitlement sideloaded apps can't get): first the
    # default port everywhere, then the next four ports and the default again
    # where nothing answered yet, in about 2.5 seconds. It runs on a thread of
    # its own with a socket of its own, so it never touches what a server
    # hosted meanwhile uses, and the servers it finds join the list on the
    # main thread (GameAgent_EnumUpdate), never while the menu draws it.
    p = src / "Engine/GameAgent/GameAgent.cpp"
    sub(p, "BOOL _bActivatedLocal = FALSE;\n", r"""BOOL _bActivatedLocal = FALSE;
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
#include "IOSNet.h"
// SEARCH LAN on a phone: the addresses on its Wi-Fi, and the query ports
// (game port + 1) of game ports 25600..25604
#define IOSLAN_MAX   1024
#define IOSLAN_PORTS 5
#define IOSLAN_FOUND 64
static unsigned int _aulIOSLan[IOSLAN_MAX];
static int _ctIOSLan = 0;
static volatile BOOL _bIOSLanBusy = FALSE;  // a search is running (main thread starts it, the thread ends it)
static pthread_mutex_t _mxIOSLan = PTHREAD_MUTEX_INITIALIZER;
static CNetworkSession *_apnsIOSLan[IOSLAN_FOUND];  // found, for the main thread to list
static INDEX _ctIOSLanFound = 0;
static BOOL _bIOSLanEnded = FALSE;  // the thread has ended: the main thread says so
static void *_IOSLan_Thread(void *pArg);
#endif
""", '#include "IOSNet.h"')
    sub(p, "  if ( !bInternet && ga_bMSLegacy) {\n", r"""  if ( !bInternet && ga_bMSLegacy) {
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
    // (a phone: a thread of its own asks every address on its Wi-Fi; a
    // search already running goes on and lists what it finds)
    if (_bIOSLanBusy) {
      return;
    }
    _ctIOSLan = IOSNet_LanTargets(_aulIOSLan, IOSLAN_MAX);
    _bIOSLanBusy = TRUE;
    _pNetwork->ga_strEnumerationStatus = ".";
    pthread_t thIOSLan;
    if (pthread_create(&thIOSLan, NULL, _IOSLan_Thread, NULL)==0) {
      pthread_detach(thIOSLan);
    } else {
      _bIOSLanBusy = FALSE;
      _pNetwork->ga_strEnumerationStatus = "";
    }
    return;
#endif
""", "    _ctIOSLan = IOSNet_LanTargets(_aulIOSLan, IOSLAN_MAX);\n")
    # the servers found go into the list here, on the main thread; this runs
    # whatever the game is doing (an intro level or a game behind the menu)
    sub(p, "extern void GameAgent_EnumUpdate(void)\n{\n", r"""extern void GameAgent_EnumUpdate(void)
{
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  pthread_mutex_lock(&_mxIOSLan);
  for (INDEX iFound=0; iFound<_ctIOSLanFound; iFound++) {
    _pNetwork->ga_lhEnumeratedSessions.AddTail(_apnsIOSLan[iFound]->ns_lnNode);
  }
  _ctIOSLanFound = 0;
  if (_bIOSLanEnded) {
    _bIOSLanEnded = FALSE;
    _pNetwork->ga_bEnumerationChange = FALSE;
    _pNetwork->ga_strEnumerationStatus = "";
  }
  pthread_mutex_unlock(&_mxIOSLan);
#endif
""", "  for (INDEX iFound=0; iFound<_ctIOSLanFound; iFound++) {\n")
    sub(p, "#ifdef PLATFORM_WIN32\nDWORD WINAPI _LocalNet_Thread(LPVOID lpParam) {\n", r"""#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
// One server's answer to \status\ (\key\value pairs), for the server list
static void _IOSLan_AddServer(char *szReply, const sockaddr_in &sinFrom, DOUBLE tmPing)
{
  CTString strPlayers, strMaxPlayers, strLevel, strGameType, strVersion, strGameName, strSessionName, strActiveMod;
  char *pch = szReply;
  while (*pch=='\\') {
    char *pchKey = pch+1;
    char *pchValue = strchr(pchKey, '\\');
    if (pchValue==NULL) break;
    *pchValue++ = 0;
    char *pchNext = strchr(pchValue, '\\');
    if (pchNext!=NULL) *pchNext = 0;
    const CTString strValue = pchValue;
    if      (!strcmp(pchKey, "gamename"))   strGameName = strValue;
    else if (!strcmp(pchKey, "gamever"))    strVersion = strValue;
    else if (!strcmp(pchKey, "hostname"))   strSessionName = strValue;
    else if (!strcmp(pchKey, "mapname"))    strLevel = strValue;
    else if (!strcmp(pchKey, "gametype"))   strGameType = strValue;
    else if (!strcmp(pchKey, "activemod"))  strActiveMod = strValue;
    else if (!strcmp(pchKey, "numplayers")) strPlayers = strValue;
    else if (!strcmp(pchKey, "maxplayers")) strMaxPlayers = strValue;
    if (pchNext==NULL) break;
    *pchNext = '\\';
    pch = pchNext;
  }
  if (strActiveMod!="") {
    strGameName = strActiveMod;
  }
  CNetworkSession *pns = new CNetworkSession;
  pns->ns_strSession = strSessionName;
  pns->ns_strAddress = inet_ntoa(sinFrom.sin_addr) + CTString(":") + CTString(0, "%d", ntohs(sinFrom.sin_port) - 1);
  pns->ns_tmPing = tmPing;
  pns->ns_strWorld = strLevel;
  pns->ns_ctPlayers = atoi(strPlayers);
  pns->ns_ctMaxPlayers = atoi(strMaxPlayers);
  pns->ns_strGameType = strGameType;
  pns->ns_strMod = strGameName;
  pns->ns_strVer = strVersion;
  pthread_mutex_lock(&_mxIOSLan);
  if (_ctIOSLanFound<IOSLAN_FOUND) {
    _apnsIOSLan[_ctIOSLanFound++] = pns;
    pns = NULL;
  }
  pthread_mutex_unlock(&_mxIOSLan);
  delete pns;  // (the list for the menu is full)
}

// Takes the answers that come in for tmWait seconds: each server once
static void _IOSLan_Receive(SOCKET sock, UBYTE *aubFound, const DOUBLE *atmSent, DOUBLE tmWait)
{
  #ifdef FIRST_ENCOUNTER
  const char *strGame = "\\gamename\\serioussam\\";
  #else
  const char *strGame = "\\gamename\\serioussamse\\";
  #endif
  const DOUBLE tmEnd = _pTimer->GetHighPrecisionTimer().GetSeconds() + tmWait;
  for (;;) {
    const DOUBLE tmLeft = tmEnd - _pTimer->GetHighPrecisionTimer().GetSeconds();
    if (tmLeft<=0) break;
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    struct timeval tv;
    tv.tv_sec = (long)tmLeft;
    tv.tv_usec = (long)((tmLeft-tv.tv_sec)*1000000.0);
    if (select(sock+1, &fds, NULL, NULL, &tv)<=0) break;
    char szReply[2050];
    sockaddr_in sinFrom;
    socklen_t slFrom = sizeof(sinFrom);
    const int iLen = recvfrom(sock, szReply, 2048, 0, (sockaddr *)&sinFrom, &slFrom);
    if (iLen<=100) continue;
    szReply[iLen] = 0;
    if (strstr(szReply, strGame)==NULL) continue;
    const INDEX iPort = ntohs(sinFrom.sin_port) - 25601;
    if (iPort<0 || iPort>=IOSLAN_PORTS) continue;
    for (INDEX i=0; i<_ctIOSLan; i++) {
      if (_aulIOSLan[i]!=sinFrom.sin_addr.s_addr) continue;
      if (!(aubFound[i]&(1<<iPort))) {
        aubFound[i] |= (1<<iPort);
        _IOSLan_AddServer(szReply, sinFrom, _pTimer->GetHighPrecisionTimer().GetSeconds()-atmSent[i]);
      }
      break;
    }
  }
}

static void *_IOSLan_Thread(void *pArg)
{
  static UBYTE aubFound[IOSLAN_MAX];  // bit p: query port 25601+p answered
  static DOUBLE atmSent[IOSLAN_MAX];
  memset(aubFound, 0, sizeof(aubFound));
  INDEX ctFound = 0;
  SOCKET sock = socket(AF_INET, SOCK_DGRAM, 0);
  if (sock!=INVALID_SOCKET) {
    int iBuffer = 256*1024;
    setsockopt(sock, SOL_SOCKET, SO_RCVBUF, (const char *)&iBuffer, sizeof(iBuffer));
    setsockopt(sock, SOL_SOCKET, SO_SNDBUF, (const char *)&iBuffer, sizeof(iBuffer));
    // (packets to addresses nobody has wait in the send buffer for a while:
    // never wait for room, and stop sending after 4 seconds)
    fcntl(sock, F_SETFL, fcntl(sock, F_GETFL)|O_NONBLOCK);
    const DOUBLE tmStopSending = _pTimer->GetHighPrecisionTimer().GetSeconds() + 4.0;
    INDEX ctSent = 0;
    // the default port everywhere first: a first packet to an address waits
    // while the phone finds it on the Wi-Fi, more of them may be dropped
    for (INDEX iRound=0; iRound<2; iRound++) {
      for (INDEX i=0; i<_ctIOSLan; i++) {
        for (INDEX iPort=0; iPort<(iRound==0 ? 1 : IOSLAN_PORTS); iPort++) {
          if (aubFound[i]&(1<<iPort)) continue;
          if (_pTimer->GetHighPrecisionTimer().GetSeconds()>tmStopSending) break;
          sockaddr_in sin;
          memset(&sin, 0, sizeof(sin));
          sin.sin_family = AF_INET;
          sin.sin_addr.s_addr = _aulIOSLan[i];
          sin.sin_port = htons(25601+iPort);
          atmSent[i] = _pTimer->GetHighPrecisionTimer().GetSeconds();
          if (sendto(sock, "\\status\\", 8, 0, (sockaddr *)&sin, sizeof(sin))<0
           && (errno==EWOULDBLOCK || errno==EAGAIN || errno==ENOBUFS)) {
            // no room: take answers for a moment, then once more
            _IOSLan_Receive(sock, aubFound, atmSent, 0.02);
            sendto(sock, "\\status\\", 8, 0, (sockaddr *)&sin, sizeof(sin));
          }
          // (a few at a time, taking answers meanwhile)
          if (++ctSent%32==0) {
            _IOSLan_Receive(sock, aubFound, atmSent, 0.003);
          }
        }
      }
      _IOSLan_Receive(sock, aubFound, atmSent, iRound==0 ? 0.5 : 1.5);
    }
    closesocket(sock);
    for (INDEX i=0; i<_ctIOSLan; i++) {
      for (INDEX iPort=0; iPort<IOSLAN_PORTS; iPort++) {
        ctFound += (aubFound[i]>>iPort)&1;
      }
    }
  }
  CPrintF("LAN search: %d addresses asked, %d games found\n", _ctIOSLan, ctFound);
  pthread_mutex_lock(&_mxIOSLan);
  _bIOSLanEnded = TRUE;
  _bIOSLanBusy = FALSE;
  pthread_mutex_unlock(&_mxIOSLan);
  return NULL;
}
#endif

#ifdef PLATFORM_WIN32
DWORD WINAPI _LocalNet_Thread(LPVOID lpParam) {
""", "static void *_IOSLan_Thread(void *pArg)\n{\n")
    # A server answers a LAN search on its query socket, which was only made
    # once the internet master server's name was found: with no internet (or
    # that name gone) nobody on the Wi-Fi saw the game. Carry on without it.
    sub(p, """    CPrintF("[%s] Couldn't resolve GameAgent server %s.\\n", _datetime, (const char *) ga_strServer);
    _uninitWinsock();
    return;
  }
""", """    CPrintF("[%s] Couldn't resolve GameAgent server %s.\\n", _datetime, (const char *) ga_strServer);
#if !(defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG))
    _uninitWinsock();
    return;
#endif
  }
""", "#if !(defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG))\n    _uninitWinsock();")
    sub(p, "  _sin->sin_addr.s_addr = *(ULONG*)phe->h_addr_list[0];\n",
"""#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  // (no master server found: games are still found on the local network,
  // and the heartbeats go to this device, where nothing listens for them)
  _sin->sin_addr.s_addr = (phe != NULL) ? *(ULONG*)phe->h_addr_list[0] : htonl(INADDR_LOOPBACK);
#else
  _sin->sin_addr.s_addr = *(ULONG*)phe->h_addr_list[0];
#endif
""", "(phe != NULL) ? *(ULONG*)phe->h_addr_list[0] : htonl(INADDR_LOOPBACK)")

    # ------------------------------------------- multiplayer: player IDs
    # A new player's ID came from rand(), never seeded: every copy of the app
    # made the same IDs, and a second phone joining a game was turned away
    # ("Player character already exists in this session").
    p = src / "Engine/Entities/PlayerCharacter.cpp"
    sub(p, """    // !!! FIXME : rcg10112001 Is this sufficient for these purposes?
    for (int i = 0; i < 16; i++)
        aub[i] = (UBYTE) (255.0 * rand() / (RAND_MAX + 1.0));
""", """#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
    // (each copy of the app its own: rand() is never seeded)
    arc4random_buf(aub, 16);
#else
    // !!! FIXME : rcg10112001 Is this sufficient for these purposes?
    for (int i = 0; i < 16; i++)
        aub[i] = (UBYTE) (255.0 * rand() / (RAND_MAX + 1.0));
#endif
""", "    arc4random_buf(aub, 16);\n")
    # The players made so far keep their IDs: a saved game finds its player
    # by them. Instead, joining someone else's game, each copy of the app
    # sends its players' IDs mixed with a key of its own (made once, kept in
    # Players\NetKey.txt), the same every time it joins.
    p = src / "GameMP/Game.cpp"
    sub(p, '#include "IOSPhotoCam.h"\n#endif\n', '#include "IOSPhotoCam.h"\nstatic void IOS_NetCharacter(CPlayerCharacter &pc);\n#endif\n',
        "static void IOS_NetCharacter(CPlayerCharacter &pc);\n")
    sub(p, "BOOL CGame::AddPlayers(void)\n{\n", """#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
// A player as sent into someone else's game: its ID mixed with this copy of
// the app's key (every copy made the same IDs from rand(), never seeded, and
// a second phone joining was turned away as a player already in the game)
static void IOS_NetCharacter(CPlayerCharacter &pc)
{
  static UBYTE aubKey[PLAYERGUIDSIZE];
  static BOOL bKey = FALSE;
  if (!bKey) {
    const CTFileName fnmKey = CTString("Players\\\\NetKey.txt");
    CTString strKey;
    BOOL bRead = FALSE;
    if (FileExists(fnmKey)) {
      LoadStringVar(fnmKey, strKey);
      bRead = TRUE;
      for (INDEX i=0; i<PLAYERGUIDSIZE && bRead; i++) {
        unsigned int uByte = 0;
        bRead = (strlen(strKey)>=(size_t)(i*2+2) && sscanf(((const char *)strKey)+i*2, "%2x", &uByte)==1);
        aubKey[i] = (UBYTE)uByte;
      }
    }
    if (!bRead) {
      arc4random_buf(aubKey, PLAYERGUIDSIZE);
      strKey = "";
      for (INDEX i=0; i<PLAYERGUIDSIZE; i++) {
        strKey += CTString(0, "%02x", (int)aubKey[i]);
      }
      strKey += "\\n";
      SaveStringVar(fnmKey, strKey);
    }
    bKey = TRUE;
  }
  for (INDEX i=0; i<PLAYERGUIDSIZE; i++) {
    pc.pc_aubGUID[i] ^= aubKey[i];
  }
}
#endif

BOOL CGame::AddPlayers(void)
{
""", "static void IOS_NetCharacter(CPlayerCharacter &pc)\n{\n")
    sub(p, """        lp.lp_pplsPlayerSource = _pNetwork->AddPlayer_t(gm_apcPlayers[iPlayer]);
""", """#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
        // (joining someone else's game: the ID with this copy's key)
        CPlayerCharacter pcIOS = gm_apcPlayers[iPlayer];
        if (!_pNetwork->IsServer()) {
          IOS_NetCharacter(pcIOS);
        }
        lp.lp_pplsPlayerSource = _pNetwork->AddPlayer_t(pcIOS);
#else
        lp.lp_pplsPlayerSource = _pNetwork->AddPlayer_t(gm_apcPlayers[iPlayer]);
#endif
""", "        CPlayerCharacter pcIOS = gm_apcPlayers[iPlayer];\n")
    sub(p, """        // demand change in game
        lp.lp_pplsPlayerSource->ChangeCharacter(pcConfig);
""", """        // demand change in game
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
        // (with the ID it joined with)
        CPlayerCharacter pcIOS = pcConfig;
        if (!_pNetwork->IsServer()) {
          IOS_NetCharacter(pcIOS);
        }
        lp.lp_pplsPlayerSource->ChangeCharacter(pcIOS);
#else
        lp.lp_pplsPlayerSource->ChangeCharacter(pcConfig);
#endif
""", "        lp.lp_pplsPlayerSource->ChangeCharacter(pcIOS);\n")

    # ------------------------------------- multiplayer: the touch controls
    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, """  // gameplay controls only while a single-player game is being played; in
  // menus, NETRICSA, demos and the intro touches are mouse clicks
""", """  // gameplay controls while a game is being played, alone or in a network
  // game (hosted or joined; not split screen); in menus, NETRICSA, demos
  // and the intro touches are mouse clicks
""", "alone or in a network\n")
    sub(p, "  if (_gmRunningGameMode==GM_SINGLE_PLAYER && _pGame->gm_bGameOn && !bMenuActive && !bMenuRendering && !bComputer) {\n",
           "  if ((_gmRunningGameMode==GM_SINGLE_PLAYER || _gmRunningGameMode==GM_NETWORK) && _pGame->gm_bGameOn && !bMenuActive && !bMenuRendering && !bComputer) {\n",
           "  if ((_gmRunningGameMode==GM_SINGLE_PLAYER || _gmRunningGameMode==GM_NETWORK) && _pGame->gm_bGameOn")
    sub(p, "  IOS_GetHudState(&hud);\n", """  IOS_GetHudState(&hud);
  // a network game: no selfies or Action Freeze (they pose the world), and
  // QUICK SAVE / QUICK LOAD only for the host of a cooperative one (whose
  // quick load restarts it for everyone, as on PC)
  hud.bNetwork = (_gmRunningGameMode==GM_NETWORK);
  hud.bNoSaves = hud.bNetwork && !(_pNetwork->IsServer()
    && ((const CSessionProperties *)_pNetwork->GetSessionProperties())->sp_bCooperative);
""", "  hud.bNetwork = (_gmRunningGameMode==GM_NETWORK);\n")
    sub(p, "  if ((iRequests&IOSTOUCH_REQ_QUICKSAVE) && iMode==IOSTOUCH_GAMEPLAY) {\n",
           "  if ((iRequests&IOSTOUCH_REQ_QUICKSAVE) && iMode==IOSTOUCH_GAMEPLAY && !hud.bNoSaves) {\n",
           "(iRequests&IOSTOUCH_REQ_QUICKSAVE) && iMode==IOSTOUCH_GAMEPLAY && !hud.bNoSaves")
    sub(p, "  if ((iRequests&IOSTOUCH_REQ_QUICKLOAD) && iMode==IOSTOUCH_GAMEPLAY) {\n",
           "  if ((iRequests&IOSTOUCH_REQ_QUICKLOAD) && iMode==IOSTOUCH_GAMEPLAY && !hud.bNoSaves) {\n",
           "(iRequests&IOSTOUCH_REQ_QUICKLOAD) && iMode==IOSTOUCH_GAMEPLAY && !hud.bNoSaves")
    # where others join a game this phone hosts, as it starts; and the iOS
    # keyboard for a menu's text field
    sub(p, """    IOS_MarkAllMessagesRead();  // the HUD's messages box stops blinking (and dims)
  }
}
#endif
""", """    IOS_MarkAllMessagesRead();  // the HUD's messages box stops blinking (and dims)
  }

  // iOS asks for Local Network access once: as the network menus open, before any search
  extern CNetworkMenu gmNetworkMenu;
  extern CNetworkJoinMenu gmNetworkJoinMenu;
  extern CNetworkStartMenu gmNetworkStartMenu;
  static BOOL bAskedLocalNetwork = FALSE;
  if (!bAskedLocalNetwork && bMenuActive && (pgmCurrentMenu==&gmNetworkMenu || pgmCurrentMenu==&gmNetworkJoinMenu
      || pgmCurrentMenu==&gmNetworkStartMenu)) {
    bAskedLocalNetwork = TRUE;
    IOSNet_AskLocalNetwork();
  }

  static BOOL bWasHosting = FALSE;
  const BOOL bHosting = _gmRunningGameMode==GM_NETWORK && _pGame->gm_bGameOn && _pNetwork->IsServer();
  if (bHosting && !bWasHosting) {
    char strAddress[64];
    CTString strMessage;
    if (IOSNet_LocalAddress(strAddress, sizeof(strAddress))) {
      const INDEX iPort = _pShell->GetINDEX("net_iPort");
      if (iPort!=25600) {
        snprintf(strAddress+strlen(strAddress), sizeof(strAddress)-strlen(strAddress), ":%d", (int)iPort);
      }
      strMessage.PrintF(TRANS("Others join at %s (or SEARCH LAN)"), strAddress);
    } else {
      strMessage = TRANS("Not on Wi-Fi: others on Wi-Fi can't join");
    }
    CPrintF("%s\\n", (const char *)strMessage);
    IOSTouch_ShowMessage((const char *)strMessage, 10.0);
    IOSNet_AskLocalNetwork(); // (and asks now, not as the first player joins)
  }
  bWasHosting = bHosting;

  extern BOOL _bEditingString;
  extern FLOAT _fIOSEditTop, _fIOSEditBottom;
  IOSTouch_MenuKeyboard(_hwndMain, bMenuActive && _bEditingString, _fIOSEditTop, _fIOSEditBottom);
}
#endif
""", "IOSTouch_MenuKeyboard(_hwndMain, bMenuActive && _bEditingString")
    sub(p, '#include "IOSTouch.h"\n#endif\n', '#include "IOSTouch.h"\n#include "IOSNet.h"\n#endif\n', '#include "IOSNet.h"')
    # A LAN or internet search only went on while no game ran at all, but the
    # intro level runs behind the menu: SEARCH LAN never found anything (nor
    # from the menu during a game).
    sub(p, """  if( _gmRunningGameMode != GM_NONE) {
    _pGame->GameMainLoop();
  // if game is not started
""", """  if( _gmRunningGameMode != GM_NONE) {
    _pGame->GameMainLoop();
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
    // (the intro level behind the menu, or a game: server searches go on)
    extern void GameAgent_EnumUpdate(void);
    GameAgent_EnumUpdate();
#endif
  // if game is not started
""", "    // (the intro level behind the menu, or a game: server searches go on)\n")

    # -------------------------------------------- multiplayer: the menus
    # Where the text field being typed into is, for the iOS keyboard to keep
    # clear of (IOSTouch_MenuKeyboard)
    p = src / "SeriousSam/Menu.cpp"
    sub(p, """  // if editing
  if (_bEditingString && pmgActive!=NULL) {
    // dim the menu  bit
    dpMenu.Fill(C_BLACK|0x40);
    // render the edit gadget again
    pmgActive->Render(&dpMenu);
  }
""", """  // if editing
  if (_bEditingString && pmgActive!=NULL) {
    // dim the menu  bit
    dpMenu.Fill(C_BLACK|0x40);
    // render the edit gadget again
    pmgActive->Render(&dpMenu);
#ifdef PLATFORM_IOS
    // (where it is on the screen, as MenuOnTouchDown takes touches)
    extern INDEX sam_bWideScreen;
    const PIXaabbox2D boxIOSEdit = FloatBoxToPixBox(&dpMenu, pmgActive->mg_boxOnScreen);
    const PIX pixIOSHeight = pdp->GetHeight();
    const PIX pixIOSOffset = sam_bWideScreen ? (PIX) ((pixIOSHeight/0.75f-pixIOSHeight)/2) : 0;
    _fIOSEditTop    = (boxIOSEdit.Min()(2)+pixIOSOffset) / (FLOAT)ClampDn(pixIOSHeight, (PIX)1);
    _fIOSEditBottom = (boxIOSEdit.Max()(2)+pixIOSOffset) / (FLOAT)ClampDn(pixIOSHeight, (PIX)1);
#endif
  }
""", "const PIXaabbox2D boxIOSEdit = FloatBoxToPixBox(&dpMenu, pmgActive->mg_boxOnScreen);")
    sub(p, "static CTimerValue _tvInitialization;\n", """#ifdef PLATFORM_IOS
// the text field being typed into, top and bottom: fractions of the screen's height
FLOAT _fIOSEditTop = 0.0f, _fIOSEditBottom = 0.0f;

// A finger lifts from the menu (the server list joins the server tapped)
void MenuOnTouchUp(void)
{
  extern void IOS_ServerListTouchUp(CMGServerList *pmg, BOOL bJoin);
  IOS_ServerListTouchUp(&mgServerList, pgmCurrentMenu==&gmServersMenu);
}
#endif
static CTimerValue _tvInitialization;
""", "void MenuOnTouchUp(void)\n{")
    sub(p, "void MenuOnTouchDown(PIX pixI, PIX pixJ)\n{\n  extern CDrawPort *pdp;\n",
"""void MenuOnTouchDown(PIX pixI, PIX pixJ)
{
  extern CDrawPort *pdp;
  // (a finger that lifted somewhere else isn't still down on the server list)
  extern void IOS_ServerListTouchUp(CMGServerList *pmg, BOOL bJoin);
  IOS_ServerListTouchUp(&mgServerList, FALSE);
""", "  IOS_ServerListTouchUp(&mgServerList, FALSE);\n")
    p = src / "SeriousSam/Menu.h"
    sub(p, "void MenuKeepSettings(void);\n#endif\n", "void MenuKeepSettings(void);\nvoid MenuOnTouchUp(void);\n#endif\n", "void MenuOnTouchUp(void);")
    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, """        } else if (msg.message==WM_RBUTTONDOWN || msg.message==WM_RBUTTONDBLCLK) {
          MenuOnKeyDown(VK_RBUTTON);
        } else if (msg.message==WM_MOUSEMOVE) {
          MenuOnMouseMove(LOWORD(msg.lParam), HIWORD(msg.lParam));
""", """        } else if (msg.message==WM_RBUTTONDOWN || msg.message==WM_RBUTTONDBLCLK) {
          MenuOnKeyDown(VK_RBUTTON);
#ifdef PLATFORM_IOS
        } else if (msg.message==WM_LBUTTONUP) {
          MenuOnTouchUp();
#endif
        } else if (msg.message==WM_MOUSEMOVE) {
          MenuOnMouseMove(LOWORD(msg.lParam), HIWORD(msg.lParam));
""", "          MenuOnTouchUp();\n")
    # The server list joined the server under a finger as it landed, so it
    # couldn't be scrolled but by its thin scroll bar: now a server joins as
    # the finger lifts from it, and dragging the list scrolls it.
    p = src / "SeriousSam/MenuGadgets.cpp"
    sub(p, "void CMGServerList::OnMouseOver(PIX pixI, PIX pixJ)\n{\n", """#ifdef PLATFORM_IOS
// a finger down on the server list: where, and whether it has dragged it
static BOOL _bIOSListPressed = FALSE;
static BOOL _bIOSListDragged = FALSE;
static CTString _strIOSListPressed;     // the server it landed on (rows move as a search finds more)
static PIX _pixIOSListPressJ = 0;
static INDEX _iIOSListPressFirst = 0;   // the first on screen then

// The finger lifts: joins the server it landed on, unless it dragged (or
// the list isn't showing: bJoin). Also as any finger lands on the menu, so
// none is still taken as down on the list.
void IOS_ServerListTouchUp(CMGServerList *pmg, BOOL bJoin)
{
  bJoin = bJoin && _bIOSListPressed && !_bIOSListDragged && _strIOSListPressed!="";
  _bIOSListPressed = FALSE;
  if (bJoin) {
    INDEX i=0;
    FOREACHINLIST(CNetworkSession, ns_lnNode, _lhServers, itns) {
      if (itns->ns_strAddress==_strIOSListPressed) {
        pmg->mg_iSelected = i;
        pmg->OnKeyDown(VK_RETURN);
        break;
      }
      i++;
    }
  }
}
#endif

void CMGServerList::OnMouseOver(PIX pixI, PIX pixJ)
{
#ifdef PLATFORM_IOS
  if (_bIOSListPressed) {
    mg_pixMouseI = pixI;
    mg_pixMouseJ = pixJ;
    // a drag of half a line scrolls the list along with the finger
    const PIX pixDrag = pixJ-_pixIOSListPressJ;
    if (Abs(pixDrag)*2>mg_pixListStepJ) {
      _bIOSListDragged = TRUE;
    }
    if (_bIOSListDragged && mg_pixListStepJ>0) {
      const INDEX ctSessions = _lhServers.Count();
      mg_iFirstOnScreen = Clamp(INDEX(_iIOSListPressFirst-pixDrag/mg_pixListStepJ), (INDEX)0, ClampDn(ctSessions-mg_ctOnScreen, (INDEX)0));
      mg_iSelected = Clamp(mg_iSelected, mg_iFirstOnScreen, mg_iFirstOnScreen+mg_ctOnScreen-1);
    }
    return;
  }
#endif
""", "void IOS_ServerListTouchUp(CMGServerList *pmg, BOOL bJoin)")
    sub(p, """  case VK_RETURN:
    PlayMenuSound(_psdPress);
    IFeel_PlayEffect("Menu_press");
    {INDEX i=0;
""", """#ifdef PLATFORM_IOS
    // (on a server: it joins as the finger lifts, unless it drags the list)
    _bIOSListPressed = TRUE;
    _bIOSListDragged = FALSE;
    _strIOSListPressed = "";
    {INDEX i=0;
    FOREACHINLIST(CNetworkSession, ns_lnNode, _lhServers, itns) {
      if (i==mg_iSelected) {
        _strIOSListPressed = itns->ns_strAddress;
      }
      i++;
    }}
    _pixIOSListPressJ = mg_pixMouseJ;
    _iIOSListPressFirst = mg_iFirstOnScreen;
    break;
#endif
  case VK_RETURN:
    PlayMenuSound(_psdPress);
    IFeel_PlayEffect("Menu_press");
    {INDEX i=0;
""", "        _strIOSListPressed = itns->ns_strAddress;\n")
    # The weapon wheel showed player 0's weapons: in a network game joined,
    # someone else's
    p = src / ("EntitiesMP/Common/HUD.cpp" if game == "SamTSE" else "Entities/Common/HUD.cpp")
    sub(p, """  CPlayer *pl = (CPlayer *)CEntity::GetPlayerEntity(0);
  if (pl==NULL || pl->m_penWeapons==NULL) return;
  CPlayerWeapons *penOld = _penWeapons;
""", """  // (this phone's player: in a network game, player 0 may be someone else's)
  CPlayer *pl = NULL;
  for (INDEX iIOSPlayer=0; iIOSPlayer<CEntity::GetMaxPlayers() && pl==NULL; iIOSPlayer++) {
    CEntity *penIOSPlayer = CEntity::GetPlayerEntity(iIOSPlayer);
    if (penIOSPlayer!=NULL && _pNetwork->IsPlayerLocal(penIOSPlayer)) {
      pl = (CPlayer *)penIOSPlayer;
    }
  }
  if (pl==NULL || pl->m_penWeapons==NULL) return;
  CPlayerWeapons *penOld = _penWeapons;
""", "  // (this phone's player: in a network game, player 0 may be someone else's)\n")
    # Joining asked for connection settings every time (a list of presets
    # from Scripts\NetSettings, which The Second Encounter's files don't have
    # at all: an empty list nothing could be picked from). A phone picks them
    # itself, by where the server is: the LAN preset on the Wi-Fi, the
    # fast-internet one otherwise.
    p = src / "SeriousSam/Menu.cpp"
    sub(p, "void StartSelectPlayersMenuFromOpen(void)\n{\n", r"""#ifdef PLATFORM_IOS
// Connection settings for the server about to be joined (as the presets in
// Scripts\NetSettings set them): LAN for an address on the local network,
// fast internet otherwise
static void IOS_ApplyNetSettings(void)
{
  int a = 0, b = 0, c = 0, d = 0;
  const BOOL bIP = sscanf(_pGame->gam_strJoinAddress, "%d.%d.%d.%d", &a, &b, &c, &d)==4;
  const BOOL bLocal = bIP && (a==10 || a==127 || (a==192 && b==168) || (a==172 && b>=16 && b<=31) || (a==169 && b==254));
  if (bLocal) {
    _pShell->Execute("cli_bPrediction=0; cli_iBufferActions=1; cli_iMinBPS=6000; cli_iMaxBPS=100000;");
  } else {
    _pShell->Execute("cli_bPrediction=1; cli_iBufferActions=2; cli_iMinBPS=6000; cli_iMaxBPS=457000;");
  }
  CPrintF("Connection settings: %s\n", bLocal ? "local network" : "internet");
}
#endif

void StartSelectPlayersMenuFromOpen(void)
{
""", "static void IOS_ApplyNetSettings(void)\n{\n")
    for parent in ("gmNetworkOpenMenu", "gmServersMenu"):
        sub(p, """  /*if (sam_strNetworkSettings=="")*/ {
    void StartNetworkSettingsMenu(void);
    StartNetworkSettingsMenu();
    gmLoadSaveMenu.gm_bNoEscape = TRUE;
    gmLoadSaveMenu.gm_pgmParentMenu = &%s;
    gmLoadSaveMenu.gm_pgmNextMenu = &gmSelectPlayersMenu;
  }
""" % parent, """#ifdef PLATFORM_IOS
  // (no connection settings to pick: they suit the server)
  IOS_ApplyNetSettings();
#else
  /*if (sam_strNetworkSettings=="")*/ {
    void StartNetworkSettingsMenu(void);
    StartNetworkSettingsMenu();
    gmLoadSaveMenu.gm_bNoEscape = TRUE;
    gmLoadSaveMenu.gm_pgmParentMenu = &%s;
    gmLoadSaveMenu.gm_pgmNextMenu = &gmSelectPlayersMenu;
  }
#endif
""" % parent, "    gmLoadSaveMenu.gm_pgmParentMenu = &%s;\n    gmLoadSaveMenu.gm_pgmNextMenu = &gmSelectPlayersMenu;\n  }\n#endif\n" % parent)
    # ------------------------------------------------ the cheat (sithewok)
    # The touch controls' cheat lives in the player entity, driven by bits in
    # the player's own actions (ios/IOSCheat.h): the same in single player and
    # in a network game, where it only acts on the player who sent them, and
    # only if the host allows it (ALLOW CHEATS, sp_bIOSAllowCheats).
    p = src / "GameMP/SessionProperties.h"
    sub(p, "  BOOL  sp_bUseExtraEnemies;  // spawn extra multiplayer enemies\n};\n",
"""  BOOL  sp_bUseExtraEnemies;  // spawn extra multiplayer enemies

  BOOL  sp_bIOSAllowCheats;   // (iOS) every player may use the touch controls' cheat on themselves
};
""", "  BOOL  sp_bIOSAllowCheats;")
    p = src / "GameMP/SessionProperties.cpp"
    sub(p, "void CGame::SetMultiPlayerSession(CSessionProperties &sp)\n{\n",
"""#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
extern INDEX gam_bIOSAllowCheats;
#endif

void CGame::SetMultiPlayerSession(CSessionProperties &sp)
{
""", "extern INDEX gam_bIOSAllowCheats;\n")
    sub(p, "  sp.sp_bInfiniteAmmo     = gam_bInfiniteAmmo    ;\n",
"""  sp.sp_bInfiniteAmmo     = gam_bInfiniteAmmo    ;
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  sp.sp_bIOSAllowCheats = gam_bIOSAllowCheats;
#endif
""", "  sp.sp_bIOSAllowCheats = gam_bIOSAllowCheats;\n")
    p = src / "GameMP/Game.cpp"
    sub(p, "INDEX gam_bQuickSave = FALSE;\n",
"""INDEX gam_bQuickSave = FALSE;
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
INDEX gam_bIOSAllowCheats = FALSE;  // (iOS) ALLOW CHEATS, a network game's host setting
#endif
""", "INDEX gam_bIOSAllowCheats = FALSE;")
    sub(p, '  _pShell->DeclareSymbol("user INDEX gam_bQuickSave;", (void *)&gam_bQuickSave);\n',
"""  _pShell->DeclareSymbol("user INDEX gam_bQuickSave;", (void *)&gam_bQuickSave);
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  _pShell->DeclareSymbol("persistent user INDEX gam_bIOSAllowCheats;", (void *)&gam_bIOSAllowCheats);
#endif
""", "(void *)&gam_bIOSAllowCheats);\n")

    # every ammo kept full
    # (in all three copies: CMake copies PlayerWeapons_old.es or HD over it)
    ammo = ["Bullets", "Shells", "Rockets", "Grenades", "Napalm", "Electricity", "IronBalls", "SniperBullets"] \
           if game == "SamTSE" else ["Bullets", "Shells", "Rockets", "Grenades", "Electricity", "IronBalls"]
    fill = "".join("    if (m_i%s<m_iMax%s) { m_i%s = m_iMax%s; }\n" % (a, a, a, a) for a in ammo)
    for f in ("PlayerWeapons.es", "PlayerWeapons_old.es", "PlayerWeaponsHD.es"):
        p = src / ("EntitiesMP" if game == "SamTSE" else "Entities") / f
        if not p.exists():
            continue
        sub(p, "  void CheatGiveAll(void) {\n",
"""  // (the touch controls' cheat) every ammo full, as it runs low
  void IOSCheatFillAmmo(void) {
""" + fill + """  };

  void CheatGiveAll(void) {
""", "  void IOSCheatFillAmmo(void) {\n")

    p = src / ("EntitiesMP/Player.es" if game == "SamTSE" else "Entities/Player.es")
    sub(p, "#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)\n// the touch controls' CAMERA takes its clean photo here (ios/IOSCapture.c)\n",
"""#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
#include "IOSCheat.h"
#else
#define IOSCHEAT_PLACT_ON     0
#define IOSCHEAT_PLACT_FLY    0
#define IOSCHEAT_PLACT_NOCLIP 0
#endif
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
// the touch controls' CAMERA takes its clean photo here (ios/IOSCapture.c)
""", '#include "IOSCheat.h"\n')
    props_anchor = (" 192 FLOAT m_tmSeriousBombFired = -10.0f,  // when the bomb was last fired\n"
                    if game == "SamTSE" else " 156 FLOAT3D m_vLocalTranslation = FLOAT3D(0,0,0),\n")
    sub(p, props_anchor, props_anchor + """
 // the touch controls' cheat (sithewok, ios/IOSCheat.h): on, flying, through walls, as the last actions said
 240 BOOL m_bIOSCheat = FALSE,
 241 BOOL m_bIOSFly = FALSE,
 242 BOOL m_bIOSNoclip = FALSE,
 243 BOOL m_bIOSPhysics = FALSE,          // its flying or noclip set the physics flags
 244 CTString m_strIOSCheatWorld = "",    // the level it last gave everything in
 245 BOOL m_bIOSWasAlive = FALSE,
 246 INDEX m_ctIOSCatches = 0,            // falls caught (the view flashes each time)
 247 INDEX m_iIOSSafeNext = 0,            // the last 4 places stood on, every 0.15 s (a ring)
 248 INDEX m_ctIOSSafe = 0,
 249 FLOAT m_tmIOSSafeLast = -100.0f,
 250 FLOAT m_tmIOSFalling = 0.0f,         // how long it has been falling
 251 FLOAT3D m_vIOSSafe0 = FLOAT3D(0,0,0),
 252 FLOAT3D m_vIOSSafe1 = FLOAT3D(0,0,0),
 253 FLOAT3D m_vIOSSafe2 = FLOAT3D(0,0,0),
 254 FLOAT3D m_vIOSSafe3 = FLOAT3D(0,0,0),
 255 ANGLE3D m_aIOSSafe0 = ANGLE3D(0,0,0),
 256 ANGLE3D m_aIOSSafe1 = ANGLE3D(0,0,0),
 257 ANGLE3D m_aIOSSafe2 = ANGLE3D(0,0,0),
 258 ANGLE3D m_aIOSSafe3 = ANGLE3D(0,0,0),
""", " 240 BOOL m_bIOSCheat = FALSE,\n")
    # once a tick, from the player's own actions
    sub(p, "    CPlayerAction paAction = paOriginal;\n",
           "    CPlayerAction paAction = paOriginal;\n    // (the touch controls' cheat, from its bits in the actions)\n    IOSCheat_Action(paOriginal.pa_ulButtons);\n",
           "    IOSCheat_Action(paOriginal.pa_ulButtons);\n")
    # its flying and noclip, in single player with the game's own cheats,
    # in a network game on their own
    sub(p, """    // wanna cheat a bit?
    if (CheatsEnabled()) {
      Cheats();
    }
""", """    // wanna cheat a bit?
    if (CheatsEnabled()) {
      Cheats();
    } else {
      IOSCheat_Physics();  // (the touch controls' cheat's flying, where the game's own cheats are off)
    }
""", "      IOSCheat_Physics();  // (the touch controls' cheat's flying")
    sub(p, "    BOOL bFlyOn = cht_bFly || cht_bGhost;\n",
           "    BOOL bFlyOn = cht_bFly || cht_bGhost || m_bIOSFly || m_bIOSNoclip;\n    m_bIOSPhysics = m_bIOSFly || m_bIOSNoclip;\n",
           "    BOOL bFlyOn = cht_bFly || cht_bGhost || m_bIOSFly || m_bIOSNoclip;\n")
    sub(p, """    if (cht_bGhost && !bIsGhost) {
      SetCollisionFlags(GetCollisionFlags() & ~((ECBI_BRUSH|ECBI_MODEL)<<ECB_TEST));
    } else if (!cht_bGhost && bIsGhost) {
""", """    if ((cht_bGhost || m_bIOSNoclip) && !bIsGhost) {
      SetCollisionFlags(GetCollisionFlags() & ~((ECBI_BRUSH|ECBI_MODEL)<<ECB_TEST));
    } else if (!(cht_bGhost || m_bIOSNoclip) && bIsGhost) {
""", "    if ((cht_bGhost || m_bIOSNoclip) && !bIsGhost) {\n")
    # nothing harms it; a fall into the abyss puts the player back
    sub(p, "    // god mode -> no one can harm you\n    if( cht_bGod && CheatsEnabled() ) { return; }\n",
"""    // the touch controls' cheat: nothing harms the player, and a fall into
    // the abyss puts them back where they last stood (if it can: otherwise
    // the fall goes on as without the cheat)
    if (m_bIOSCheat) {
      if (dmtType!=DMT_ABYSS || IOSCheat_CatchFall()) { return; }
    }

    // god mode -> no one can harm you
    if( cht_bGod && CheatsEnabled() ) { return; }
""", "      if (dmtType!=DMT_ABYSS || IOSCheat_CatchFall()) { return; }\n")
    bombs = "    m_iSeriousBombCount = 3;\n" if game == "SamTSE" else ""
    sub(p, "  // check if cheats can be active\n  BOOL CheatsEnabled(void)\n", """  // ---- the touch controls' cheat (sithewok, ios/IOSCheat.h) ----

  // whether this player may use it: alone, or in a network game whose host allows it
  BOOL IOSCheat_Allowed(void)
  {
    return GetSP()->sp_ctMaxPlayers==1 || GetSP()->sp_bQuickTest || GetSP()->sp_bIOSAllowCheats;
  }

  // one of the last places stood on (a ring of 4)
  FLOAT3D *IOSCheat_SafePos(INDEX i)
  {
    // (ECC takes no switch's default: here)
    if ((i&3)==0) { return &m_vIOSSafe0; }
    if ((i&3)==1) { return &m_vIOSSafe1; }
    if ((i&3)==2) { return &m_vIOSSafe2; }
    return &m_vIOSSafe3;
  }
  ANGLE3D *IOSCheat_SafeRot(INDEX i)
  {
    if ((i&3)==0) { return &m_aIOSSafe0; }
    if ((i&3)==1) { return &m_aIOSSafe1; }
    if ((i&3)==2) { return &m_aIOSSafe2; }
    return &m_aIOSSafe3;
  }

  // everything: all weapons and their ammo, full health and armour
  void IOSCheat_GiveAll(void)
  {
    ((CPlayerWeapons&)*m_penWeapons).CheatGiveAll();
    if (GetHealth()<TopHealth()) { SetHealth(TopHealth()); }
    if (m_fArmor<TopArmor()) { m_fArmor = TopArmor(); }
%BOMBS%  }

  // A fall caught: back to the oldest of the last places stood on (about half
  // a second before the fall), still. FALSE if there is none.
  BOOL IOSCheat_CatchFall(void)
  {
    // (never while the game walks the player: a cutscene could wait for them forever)
    if (m_ctIOSSafe<=0 || m_penActionMarker!=NULL) { return FALSE; }
    const INDEX iOldest = (m_iIOSSafeNext-m_ctIOSSafe)&3;
    CPlacement3D pl(*IOSCheat_SafePos(iOldest), *IOSCheat_SafeRot(iOldest));
    // (that place is used up: one that drops the player again isn't used twice)
    m_ctIOSSafe--;
    Teleport(pl, FALSE);
    ForceFullStop();
    m_tmIOSFalling = 0.0f;
    m_ctIOSCatches++;
    return TRUE;
  }

  // Once a tick, from the player's actions (every machine in a network game
  // runs it alike, from the same actions)
  void IOSCheat_Action(ULONG ulButtons)
  {
    const BOOL bWasOn = m_bIOSCheat;
    m_bIOSCheat = (ulButtons&IOSCHEAT_PLACT_ON) && IOSCheat_Allowed();
    // (not while the game walks the player: a cutscene, a level's start)
    m_bIOSFly = m_bIOSCheat && (ulButtons&IOSCHEAT_PLACT_FLY) && m_penActionMarker==NULL;
    m_bIOSNoclip = m_bIOSCheat && (ulButtons&IOSCHEAT_PLACT_NOCLIP) && m_penActionMarker==NULL;
    const BOOL bAlive = (GetFlags()&ENF_ALIVE) ? TRUE : FALSE;
    const BOOL bWasAlive = m_bIOSWasAlive;
    m_bIOSWasAlive = bAlive;
    if (!m_bIOSCheat || !bAlive) {
      m_tmIOSFalling = 0.0f;
      return;
    }
    // everything given as it comes on, at the start of each level and after
    // being reborn (the places stood on start over then too)
    const CTString strWorld = GetWorld()->wo_fnmFileName;
    if (!bWasOn || !bWasAlive || m_strIOSCheatWorld!=strWorld) {
      m_strIOSCheatWorld = strWorld;
      m_ctIOSSafe = 0;
      IOSCheat_GiveAll();
    }
    ((CPlayerWeapons&)*m_penWeapons).IOSCheatFillAmmo();
    // where it stands, every 0.15 s, for a fall into a pit: only on the
    // level's own ground (not a lift, a door, a crate or an enemy, which may
    // have gone by then). Flying or through walls, and after a jump of more
    // than 4 m between two of them (a teleporter), they start over.
    const FLOAT tmNow = _pTimer->CurrentTick();
    if (m_bIOSFly || m_bIOSNoclip) { m_ctIOSSafe = 0; }
    CEntity *penIOSGround = en_penReference;
    const BOOL bStanding = penIOSGround!=NULL && !m_bIOSFly && !m_bIOSNoclip;
    const BOOL bOnGround = bStanding && penIOSGround->en_RenderType==CEntity::RT_BRUSH
                        && !(penIOSGround->en_ulPhysicsFlags&EPF_MOVABLE);
    if (bOnGround && tmNow-m_tmIOSSafeLast>=0.15f) {
      m_tmIOSSafeLast = tmNow;
      if (m_ctIOSSafe>0 && (GetPlacement().pl_PositionVector-*IOSCheat_SafePos(m_iIOSSafeNext-1)).Length()>4.0f) {
        m_ctIOSSafe = 0;
      }
      *IOSCheat_SafePos(m_iIOSSafeNext) = GetPlacement().pl_PositionVector;
      *IOSCheat_SafeRot(m_iIOSSafeNext) = GetPlacement().pl_OrientationAngle;
      m_iIOSSafeNext = (m_iIOSSafeNext+1)&3;
      m_ctIOSSafe = Min(m_ctIOSSafe+1, INDEX(4));
    }
    // falling for 3 s on end (a pit with no bottom that hurts): caught too
    const FLOAT fDown = en_vCurrentTranslationAbsolute%en_vGravityDir;
    if (!bStanding && !m_bIOSFly && !m_bIOSNoclip && fDown>5.0f) {
      m_tmIOSFalling += _pTimer->TickQuantum;
      if (m_tmIOSFalling>3.0f) {
        IOSCheat_CatchFall();
      }
    } else {
      m_tmIOSFalling = 0.0f;
    }
  }

  // its flying and noclip where the game's own cheats are off (a network
  // game, a cutscene); in single player Cheats() does it
  void IOSCheat_Physics(void)
  {
    const BOOL bFlyOn = m_bIOSFly || m_bIOSNoclip;
    if (!bFlyOn && !m_bIOSPhysics) { return; }
    m_bIOSPhysics = bFlyOn;
    const BOOL bIsFlying = !(GetPhysicsFlags() & EPF_TRANSLATEDBYGRAVITY);
    if (bFlyOn && !bIsFlying) {
      SetPhysicsFlags(GetPhysicsFlags() & ~(EPF_TRANSLATEDBYGRAVITY|EPF_ORIENTEDBYGRAVITY));
      en_plViewpoint.pl_OrientationAngle = ANGLE3D(0, 0, 0);
    } else if (!bFlyOn && bIsFlying) {
      SetPhysicsFlags(GetPhysicsFlags() | EPF_TRANSLATEDBYGRAVITY|EPF_ORIENTEDBYGRAVITY);
      en_plViewpoint.pl_OrientationAngle = ANGLE3D(0, 0, 0);
    }
    const BOOL bIsGhost = !(GetCollisionFlags() & ((ECBI_BRUSH|ECBI_MODEL)<<ECB_TEST));
    if (m_bIOSNoclip && !bIsGhost) {
      SetCollisionFlags(GetCollisionFlags() & ~((ECBI_BRUSH|ECBI_MODEL)<<ECB_TEST));
    } else if (!m_bIOSNoclip && bIsGhost) {
      SetCollisionFlags(GetCollisionFlags() | ((ECBI_BRUSH|ECBI_MODEL)<<ECB_TEST));
    }
  }

  // check if cheats can be active
  BOOL CheatsEnabled(void)
""".replace("%BOMBS%", bombs), "  BOOL IOSCheat_Allowed(void)\n")
    # the cheat's bits in local player 0's actions (Game.cpp), and its word
    # typed in the console (Console.cpp), both through the app's pointers
    p = src / "GameMP/Game.cpp"
    sub(p, "static void IOS_NetCharacter(CPlayerCharacter &pc);\n#endif\n",
"""static void IOS_NetCharacter(CPlayerCharacter &pc);
#endif
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
#include "IOSCheat.h"
// (set by the app: ios/IOSCheat.h)
unsigned long (*IOSCheat_pfnActionBits)(void) = NULL;
void (*IOSCheat_pfnTyped)(void) = NULL;
#endif
""", "unsigned long (*IOSCheat_pfnActionBits)(void) = NULL;\n")
    sub(p, "  }\n#endif\n}\n\nCButtonAction &CControls::AddButtonAction(void)\n",
"""  }
#endif
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  // the touch controls' cheat (sithewok): on, flying, through walls, for the
  // first local player
  if (ctl_iCurrentPlayerLocal==0 && IOSCheat_pfnActionBits!=NULL) {
    paAction.pa_ulButtons |= (ULONG)IOSCheat_pfnActionBits();
  }
#endif
}

CButtonAction &CControls::AddButtonAction(void)
""", "    paAction.pa_ulButtons |= (ULONG)IOSCheat_pfnActionBits();\n")
    p = src / "GameMP/Console.cpp"
    sub(p, '#include "LCDDrawing.h"\n',
"""#include "LCDDrawing.h"
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
#include "IOSCheat.h"
#endif
""", '#include "IOSCheat.h"\n')
    sub(p, '  // check for cheats\n  #define CHEAT_PREFIX "please"\n',
"""#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  // the touch controls' cheat word (sithewok, in any case, with or without a
  // '/'): it switches the cheat on or off, and isn't sent as a chat line
  {
    const char *strIOSWord = strEditingLine;
    if (strIOSWord[0]=='/') { strIOSWord++; }
    if (strcasecmp(strIOSWord, IOSCHEAT_WORD)==0) {
      strEditingLine = "";
      iCursorPos = 0;
      if (IOSCheat_pfnTyped!=NULL) { IOSCheat_pfnTyped(); }
      return;
    }
  }
#endif

  // check for cheats
  #define CHEAT_PREFIX "please"
""", "    if (strcasecmp(strIOSWord, IOSCHEAT_WORD)==0) {\n")
    # The app's part of the cheat: the overlay's bits and the typed word to
    # the game (IOSCheat.h), what the overlay needs to know, and its
    # requests (one of Sam's lines, the level picked)
    p = src / "SeriousSam/SeriousSam.cpp"
    sub(p, '#include "IOSTouch.h"\n#include "IOSNet.h"\n#endif\n',
           '#include "IOSTouch.h"\n#include "IOSNet.h"\n#include "IOSCheat.h"\n#include "IOSCheatGame.h"\n#endif\n',
           '#include "IOSCheatGame.h"\n')
    sub(p, """  hud.bNetwork = (_gmRunningGameMode==GM_NETWORK);
""", """  hud.bNetwork = (_gmRunningGameMode==GM_NETWORK);
  // the cheat (sithewok): the overlay drives it (IOSCheat.h)
  IOSCheat_pfnActionBits = IOSTouch_CheatBits;
  IOSCheat_pfnTyped = IOSTouch_CheatTyped;
  hud.bCheatAllowed = IOSCheatGame_Allowed();
  hud.ctLevels = IOSCheatGame_NumLevels();
  hud.ctCatches = IOSCheatGame_Catches();
  hud.uWorld = IOSCheatGame_World();
""", "  IOSCheat_pfnActionBits = IOSTouch_CheatBits;\n")
    sub(p, """  if ((iRequests&IOSTOUCH_REQ_READMESSAGES) && iMode==IOSTOUCH_GAMEPLAY) {
""", """  if (iRequests&IOSTOUCH_REQ_CHEATSOUND) {
    IOSCheatGame_PlaySound();  // (the cheat came on: one of Sam's lines)
  }
  if ((iRequests&IOSTOUCH_REQ_LEVEL) && iMode==IOSTOUCH_GAMEPLAY) {
    if (!IOSCheatGame_GoToLevel(IOSTouch_TakeLevelPick())) {  // (the cheat's level picker)
      IOSTouch_CheatLevelFailed();
    }
  }
  if ((iRequests&IOSTOUCH_REQ_READMESSAGES) && iMode==IOSTOUCH_GAMEPLAY) {
""", "IOSCheatGame_GoToLevel(IOSTouch_TakeLevelPick())) {")
    # ALLOW CHEATS on START SERVER: whether every player may use the cheat
    # on themselves in the game hosted (gam_bIOSAllowCheats; off unless set)
    p = src / "SeriousSam/Menu.cpp"
    sub(p, "CMGTrigger mgNetworkVisible;\n", """CMGTrigger mgNetworkVisible;
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
CMGTrigger mgNetworkAllowCheats;
#endif
""", "CMGTrigger mgNetworkAllowCheats;\n")
    sub(p, """  mgNetworkGameOptions.mg_pmgUp = &mgNetworkVisible;
  mgNetworkGameOptions.mg_pmgDown = &mgNetworkStartStart;
""", """  mgNetworkGameOptions.mg_pmgUp = &mgNetworkVisible;
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  mgNetworkGameOptions.mg_pmgDown = &mgNetworkAllowCheats;
#else
  mgNetworkGameOptions.mg_pmgDown = &mgNetworkStartStart;
#endif
""", "  mgNetworkGameOptions.mg_pmgDown = &mgNetworkAllowCheats;\n")
    sub(p, """  // start button
  mgNetworkStartStart.mg_bfsFontSize = BFS_LARGE;
  mgNetworkStartStart.mg_boxOnScreen = BoxBigRow(7, _fGlobalButtonAdjuster);
  mgNetworkStartStart.mg_pmgUp = &mgNetworkGameOptions;
""", """#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  // (iOS) the touch controls' cheat for every player, on themselves
  TRIGGER_MG(mgNetworkAllowCheats, 9,
       mgNetworkGameOptions, mgNetworkStartStart, TRANS("Allow cheats:"), astrNoYes);
  mgNetworkAllowCheats.mg_strTip = TRANS("if on, every player can use the cheat (sithewok) on themselves");
#endif

  // start button
  mgNetworkStartStart.mg_bfsFontSize = BFS_LARGE;
  mgNetworkStartStart.mg_boxOnScreen = BoxBigRow(7, _fGlobalButtonAdjuster);
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  mgNetworkStartStart.mg_pmgUp = &mgNetworkAllowCheats;
#else
  mgNetworkStartStart.mg_pmgUp = &mgNetworkGameOptions;
#endif
""", "  mgNetworkStartStart.mg_pmgUp = &mgNetworkAllowCheats;\n")
    sub(p, "  mgNetworkVisible.ApplyCurrentSelection();\n", """  mgNetworkVisible.ApplyCurrentSelection();
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  mgNetworkAllowCheats.mg_iSelected = Clamp(_pShell->GetINDEX("gam_bIOSAllowCheats"), (INDEX)0, (INDEX)1);
  mgNetworkAllowCheats.ApplyCurrentSelection();
#endif
""", '  mgNetworkAllowCheats.mg_iSelected = Clamp(_pShell->GetINDEX("gam_bIOSAllowCheats"), (INDEX)0, (INDEX)1);\n')
    sub(p, '  _pShell->SetINDEX("ser_bEnumeration", mgNetworkVisible.mg_iSelected);\n', """  _pShell->SetINDEX("ser_bEnumeration", mgNetworkVisible.mg_iSelected);
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
  _pShell->SetINDEX("gam_bIOSAllowCheats", mgNetworkAllowCheats.mg_iSelected);
#endif
""", '  _pShell->SetINDEX("gam_bIOSAllowCheats", mgNetworkAllowCheats.mg_iSelected);\n')
    # (a network game goes on behind the menu, the console or NETRICSA,
    # where the player's buttons are let go of: the cheat stays on)
    p = src / "GameMP/Game.cpp"
    sub(p, "        paClearAction.pa_ulButtons     = 0;\n", """        paClearAction.pa_ulButtons     = 0;
#if defined(PLATFORM_IOS) || defined(IOS_CAMERA_RIG)
        // (but not the touch controls' cheat: in a network game the game goes on)
        if (iPlayer==0 && IOSCheat_pfnActionBits!=NULL) {
          paClearAction.pa_ulButtons = (ULONG)IOSCheat_pfnActionBits();
        }
#endif
""", "          paClearAction.pa_ulButtons = (ULONG)IOSCheat_pfnActionBits();\n")
    print(game, "patched")
