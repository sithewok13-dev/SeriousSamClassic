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
// USE works like the default Use key (ctl_bUseOrComputer): use, and tapped
// again within ctl_tmComputerDoubleClick NETRICSA -- or both at once, if the
// player's settings say NETRICSA opens on a single click. But it never works
// the sniper scope, which that key does when there is nothing to use: it
// sends no USE_HELD or SNIPER_USE, and USE_NOZOOM with its press. ZOOM is
// the scope: plain use (with the sniper rifle: scope on/off, held: zoom in).
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
      ulActions |= IOS_PLACT_USE_NOZOOM;
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
// With PLACT_USE or PLACT_COMPUTER from the touch controls' USE (GameMP/Game.cpp):
// that use never works the sniper scope (their ZOOM button does), and with the
// sniper rifle opens NETRICSA as with any other weapon.
#define PLACT_USE_NOZOOM          (1L<<19)
#else
#define PLACT_USE_NOZOOM          0
#endif
""", "#define PLACT_USE_NOZOOM")
        sub(p, """    if (ulNewButtons&PLACT_USE) {
      if (((CPlayerWeapons&)*m_penWeapons).m_iCurrentWeapon==WEAPON_SNIPER) {
""", """    if (ulNewButtons&PLACT_USE) {
      // (the iOS touch controls' USE: as with any weapon, see PLACT_USE_NOZOOM)
      if (((CPlayerWeapons&)*m_penWeapons).m_iCurrentWeapon==WEAPON_SNIPER && !(ulButtonsNow&PLACT_USE_NOZOOM)) {
""", "WEAPON_SNIPER && !(ulButtonsNow&PLACT_USE_NOZOOM)")
        sub(p, """    else if (!bSomethingToUse)
    {
""", """    // nothing to use: the sniper scope on or off (not for the iOS touch controls' USE)
    else if (!bSomethingToUse && !(ulButtonsNow&PLACT_USE_NOZOOM))
    {
""", "!bSomethingToUse && !(ulButtonsNow&PLACT_USE_NOZOOM)")

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
#endif
      const FLOAT tmIn = 0.5f;
""", "      fRow = fRowIOSMsg;\n")
    sub(p, "        fCol-=fAdvUnit*15*fRatio;\n",
"""        fCol-=fAdvUnit*15*fRatio;
#ifdef PLATFORM_IOS
        fRow = fRowIOSMsg+fAdvUnit*5*fRatio;
        fCol = fColIOSMsg;
#endif
""", "fRow = fRowIOSMsg+fAdvUnit*5*fRatio;")
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
    # The Second Encounter's power-ups go in the top row, in the gap between
    # the score and the high score: above the ammo row at the bottom right,
    # as on PC, they sat under the touch controls' FIRE (and ZOOM), and they
    # blink, and beep, as they run out. Drawn once the top row's sizes are
    # known; the same boxes, icons, bars and sound as on PC, left to right.
    if game == "SamTSE":
        sub(p, "  // draw powerup(s) if needed\n",
"""  // draw powerup(s) if needed
#ifndef PLATFORM_IOS  // (iOS: in the top row, below)
""", "#ifndef PLATFORM_IOS  // (iOS: in the top row, below)")
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

    print(game, "patched")
