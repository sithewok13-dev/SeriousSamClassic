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

    print(game, "patched")
