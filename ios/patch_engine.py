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

    print(game, "patched")
