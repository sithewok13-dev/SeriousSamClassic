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
#else
#define IOS_PLACT_USE_HELD    (1L<<9)
#define IOS_PLACT_SNIPER_USE  (1L<<12)
#define IOS_PLACT_FIREBOMB    (1L<<13)
#endif

// The touch controls' buttons as the player's button bits for this tick.
// USE works like the default Use key (ctl_bUseOrComputer): use, and tapped
// again within ctl_tmComputerDoubleClick NETRICSA -- or both at once, if the
// player's settings say NETRICSA opens on a single click. ZOOM is plain use
// (with the sniper rifle: scope on/off, held: zoom in).
static ULONG IOS_TouchButtonActions(const CPlayerCharacter &pc, ULONG ulTouch)
{
  static ULONG ulTouchLast = 0;
  static TIME tmLastUse = -100.0;
  ULONG ulActions = 0;
  if (ulTouch&IOSTOUCH_FIRE)       ulActions |= IOS_PLACT_FIRE;
  if (ulTouch&IOSTOUCH_NEXTWEAPON) ulActions |= IOS_PLACT_WEAPON_NEXT;
  if (ulTouch&IOSTOUCH_PREVWEAPON) ulActions |= IOS_PLACT_WEAPON_PREV;
  if (ulTouch&IOSTOUCH_BOMB)       ulActions |= IOS_PLACT_FIREBOMB;
  if (ulTouch&IOSTOUCH_ZOOM)       ulActions |= IOS_PLACT_USE|IOS_PLACT_USE_HELD|IOS_PLACT_SNIPER_USE;
  if (ulTouch&IOSTOUCH_USE) {
    ulActions |= IOS_PLACT_USE_HELD|IOS_PLACT_SNIPER_USE;
    // just pressed
    if (!(ulTouchLast&IOSTOUCH_USE)) {
      const CPlayerSettings *pps = (const CPlayerSettings *)pc.pc_aubAppearance;
      const FLOAT tmDoubleClick = _pShell->GetFLOAT("ctl_tmComputerDoubleClick");
      const TIME tmNow = _pTimer->GetRealTimeTick();
      if (tmDoubleClick==0 || (pps->ps_ulFlags&PSF_COMPSINGLECLICK)) {
        ulActions |= IOS_PLACT_USE|IOS_PLACT_COMPUTER;
      } else {
        ulActions |= (tmNow<=tmLastUse+tmDoubleClick) ? IOS_PLACT_COMPUTER : IOS_PLACT_USE;
      }
      tmLastUse = tmNow;
    }
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
    paAction.pa_ulButtons |= IOS_TouchButtonActions(pc, tiTouch.ulButtons);
  }
#endif
}
""", "IOSTouch_ReadInput(&tiTouch);")

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
    # once the game is back. A real mouse or trackpad still does both.
    sub(p, "static Sint16 mouse_relative_y = 0;\n",
"""static Sint16 mouse_relative_y = 0;
#ifdef PLATFORM_IOS
// mouse movement for looking, from a real mouse or trackpad only
static SDL_atomic_t _iIOSMouseDX, _iIOSMouseDY;
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
            if (event->button.which == SDL_TOUCH_MOUSEID) break;  // a touch: a menu click, not a mouse button
#endif
            if (event->button.button <= 5) {
""", "if (event->button.which == SDL_TOUCH_MOUSEID) break;")
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
}
#endif

// automaticaly manage pause toggling
static void UpdatePauseState(void)
""", "static void IOS_UpdateTouchControls(void)")
    sub(p, "      IOS_WaitForForeground();\n    }\n#endif\n",
           "      IOS_WaitForForeground();\n    }\n    IOS_UpdateTouchControls();\n#endif\n",
        "    IOS_UpdateTouchControls();\n")

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

    # the HUD tells the overlay where its score and high score boxes and ammo
    # row are, and what the player holds (sniper rifle, serious bombs)
    p = src / ("EntitiesMP/Common/HUD.cpp" if game == "SamTSE" else "Entities/Common/HUD.cpp")
    sub(p, "// draw border with filter\nstatic void HUD_DrawBorder(",
"""#ifdef PLATFORM_IOS
#include "IOSTouch.h"
// What the touch controls need to know (IOS_GetHudState): where the score
// and high score boxes, the ammo row and the unread messages box are, so
// they keep their buttons clear of them, and what the player holds. Boxes
// are gathered as HUD_DrawBorder draws them, in fractions of the screen.
enum { IOS_HUD_NONE = 0, IOS_HUD_SCORE, IOS_HUD_HISCORE, IOS_HUD_AMMO, IOS_HUD_MESSAGES };
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
            : (_iIOSHudPart==IOS_HUD_AMMO) ? _hudIOS.afAmmo : _hudIOS.afMessages;
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
    # the unread messages box, measured where it sits when it shows (it
    # slides in and out, and only shows while there are unread messages)
    sub(p, "    // prepare and draw unread messages\n",
"""#ifdef PLATFORM_IOS
    {
      const FLOAT fRowM = hud_bLegacyHUD ? pixTopBound+fHalfUnit
                        : pixBottomBound-(fNextUnit+fHalfUnit)*_fArmorHeightAdjuster-21.0f;
      const FLOAT fColM = pixRightBound-fHalfUnit-fAdvUnit-fChrUnit*4;
      const FLOAT fAdvM = fAdvUnit+fChrUnit*4/2-fHalfUnit;
      _iIOSHudPart = IOS_HUD_MESSAGES;
      _bIOSHudMeasureOnly = TRUE;
      HUD_DrawBorder( fColM,       fRowM, fOneUnit,   fOneUnit, colBorder);
      HUD_DrawBorder( fColM+fAdvM, fRowM, fChrUnit*4, fOneUnit, colBorder);
      _bIOSHudMeasureOnly = FALSE;
      _iIOSHudPart = IOS_HUD_NONE;
    }
#endif
    // prepare and draw unread messages
""", "_iIOSHudPart = IOS_HUD_MESSAGES;")
    # the leftmost ammo box is this many boxes left of the rightmost one: all
    # 8 ammo types, plus the serious bomb in the Second Encounter
    ctAmmoAdv = 8 if game == "SamTSE" else 7
    sub(p, "  FillWeaponAmmoTables();\n",
"""  FillWeaponAmmoTables();
#ifdef PLATFORM_IOS
  // the ammo row at its widest, whatever the player has now, so the touch
  // controls don't move about as ammo is picked up
  {
    const FLOAT fScalingAdjustment = _fCustomScalingAdjustment;
    if (!hud_bLegacyHUD) {_fCustomScalingAdjustment = 0.7f;}
    _iIOSHudPart = IOS_HUD_AMMO;
    _bIOSHudMeasureOnly = TRUE;
    HUD_DrawBorder( fCol,             fRow, fOneUnitS, fOneUnitS, colBorder);
    HUD_DrawBorder( fCol-%d*fAdvUnitS, fRow, fOneUnitS, fOneUnitS, colBorder);
    _bIOSHudMeasureOnly = FALSE;
    _iIOSHudPart = IOS_HUD_NONE;
    _fCustomScalingAdjustment = fScalingAdjustment;
  }
#endif
""" % ctAmmoAdv, "_iIOSHudPart = IOS_HUD_AMMO;")
    if game == "SamTSE":
        strHolds = """  _hudIOS.bSniper = (_penWeapons->m_iCurrentWeapon==WEAPON_SNIPER);
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

    print(game, "patched")
