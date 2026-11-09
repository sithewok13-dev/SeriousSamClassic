/* The OpenGL ES that gl4es draws with on iOS: ANGLE (Metal), else Apple's.
   See IOSGL.h. */

#define IOSGL_IMPLEMENTATION
#include "IOSGL.h"

#include <SDL.h>
#include <SDL_metal.h>

// (only through the pointers below: ANGLE is loaded at run time, so that
// the app still starts, on Apple's OpenGL ES, without it)
#define EGL_EGL_PROTOTYPES 0
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <EGL/eglext_angle.h>

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

enum { GL_NONE_YET = 0, GL_ANGLE, GL_APPLE };
static int _iUsing = GL_NONE_YET;

#define IOSGL_EGL_FUNCTIONS(X) \
  X(PFNEGLGETPROCADDRESSPROC, eglGetProcAddress) X(PFNEGLGETPLATFORMDISPLAYPROC, eglGetPlatformDisplay) \
  X(PFNEGLGETERRORPROC, eglGetError) X(PFNEGLINITIALIZEPROC, eglInitialize) X(PFNEGLTERMINATEPROC, eglTerminate) \
  X(PFNEGLBINDAPIPROC, eglBindAPI) X(PFNEGLCHOOSECONFIGPROC, eglChooseConfig) \
  X(PFNEGLGETCONFIGATTRIBPROC, eglGetConfigAttrib) X(PFNEGLCREATECONTEXTPROC, eglCreateContext) \
  X(PFNEGLCREATEWINDOWSURFACEPROC, eglCreateWindowSurface) X(PFNEGLMAKECURRENTPROC, eglMakeCurrent) \
  X(PFNEGLSWAPBUFFERSPROC, eglSwapBuffers) X(PFNEGLSWAPINTERVALPROC, eglSwapInterval) \
  X(PFNEGLQUERYSURFACEPROC, eglQuerySurface) X(PFNEGLQUERYSTRINGPROC, eglQueryString) \
  X(PFNEGLDESTROYSURFACEPROC, eglDestroySurface) X(PFNEGLDESTROYCONTEXTPROC, eglDestroyContext)
#define IOSGL_DECLARE(type, name) static type p_##name = NULL;
IOSGL_EGL_FUNCTIONS(IOSGL_DECLARE)
#undef IOSGL_DECLARE

static void *_hAppleGLES = NULL;
static EGLDisplay _dpy = EGL_NO_DISPLAY;
static EGLConfig _cfg = NULL;
static EGLContext _ctx = EGL_NO_CONTEXT;
static EGLSurface _surf = EGL_NO_SURFACE;
static SDL_MetalView _view = NULL;
static int _iSwapInterval = 1;
static int _bBackwardsCompat = 0;  // EGL_ANGLE_create_context_backwards_compatible

/* ------------------------------------------------------------ start guard */

// A file that's there while ANGLE is starting (until 30 frames are shown):
// if it's still there at the next launch, that launch uses Apple's OpenGL ES
// (once; the one after tries ANGLE again)
#define IOSGL_GUARD_FRAMES 30
static int _ctGuardFrames = -1;  // (-1: not guarding)

static const char *IOSGL_GuardPath(void)
{
  static char strPath[1100] = "";
  if (strPath[0] == 0) {
    const char *strHome = getenv("HOME");
    snprintf(strPath, sizeof(strPath), "%s/Library/angle-starting", strHome ? strHome : ".");
  }
  return strPath;
}

static int IOSGL_LastStartFailed(void)
{
  if (access(IOSGL_GuardPath(), F_OK) != 0) return 0;
  unlink(IOSGL_GuardPath());
  return 1;
}

static void IOSGL_GuardBegin(void)
{
  FILE *f = fopen(IOSGL_GuardPath(), "w");
  if (f != NULL) fclose(f);
  _ctGuardFrames = 0;
}

static void IOSGL_GuardEnd(void)
{
  _ctGuardFrames = -1;
  unlink(IOSGL_GuardPath());
}

/* ------------------------------------------------------------------ ANGLE */

static int IOSGL_Fail(const char *strWhat)
{
  printf("iOS: graphics: ANGLE: %s (EGL error 0x%04X)\n", strWhat, p_eglGetError ? (unsigned) p_eglGetError() : 0u);
  return 0;
}

// ANGLE's two frameworks, in the app's Frameworks folder
static void *IOSGL_LoadFramework(const char *strName)
{
  char strPath[1200];
  char *strBase = SDL_GetBasePath();
  snprintf(strPath, sizeof(strPath), "%sFrameworks/%s.framework/%s", strBase ? strBase : "", strName, strName);
  SDL_free(strBase);
  void *h = dlopen(strPath, RTLD_NOW | RTLD_LOCAL);
  if (h == NULL) printf("iOS: graphics: ANGLE: can't load %s: %s\n", strName, dlerror());
  return h;
}

// Loads ANGLE and sets up its Metal display and a config. Touches no window.
static int IOSGL_ProbeANGLE(void)
{
  if (IOSGL_LoadFramework("libGLESv2") == NULL) return 0;
  void *hEGL = IOSGL_LoadFramework("libEGL");
  if (hEGL == NULL) return 0;
#define IOSGL_RESOLVE(type, name) \
  p_##name = (type) dlsym(hEGL, #name); \
  if (p_##name == NULL) return IOSGL_Fail("no " #name);
  IOSGL_EGL_FUNCTIONS(IOSGL_RESOLVE)
#undef IOSGL_RESOLVE

  const EGLAttrib aPlatform[] = { EGL_PLATFORM_ANGLE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE, EGL_NONE };
  _dpy = p_eglGetPlatformDisplay(EGL_PLATFORM_ANGLE_ANGLE, (void *)(uintptr_t) EGL_DEFAULT_DISPLAY, aPlatform);
  if (_dpy == EGL_NO_DISPLAY) return IOSGL_Fail("no Metal display");
  EGLint iMajor = 0, iMinor = 0;
  if (!p_eglInitialize(_dpy, &iMajor, &iMinor)) {
    _dpy = EGL_NO_DISPLAY;
    return IOSGL_Fail("eglInitialize failed");
  }
  const char *strExt = p_eglQueryString(_dpy, EGL_EXTENSIONS);
  _bBackwardsCompat = strExt != NULL && strstr(strExt, "EGL_ANGLE_create_context_backwards_compatible") != NULL;
  if (!p_eglBindAPI(EGL_OPENGL_ES_API)) return IOSGL_Fail("eglBindAPI failed");
  // what Apple's OpenGL ES gave the engine, at least: 8-bit colour, 24-bit
  // depth (the engine asks for 16 to 32) and 8-bit stencil
  const EGLint aConfig[] = {
    EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
    EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
    EGL_DEPTH_SIZE, 24, EGL_STENCIL_SIZE, 8, EGL_NONE
  };
  EGLint ctConfigs = 0;
  if (!p_eglChooseConfig(_dpy, aConfig, &_cfg, 1, &ctConfigs) || ctConfigs < 1) return IOSGL_Fail("no config");
  printf("iOS: graphics: ANGLE: EGL %d.%d, %s\n", (int) iMajor, (int) iMinor, p_eglQueryString(_dpy, EGL_VERSION));
  return 1;
}

static void IOSGL_DestroyANGLE(void)
{
  if (_dpy != EGL_NO_DISPLAY) {
    p_eglMakeCurrent(_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (_surf != EGL_NO_SURFACE) p_eglDestroySurface(_dpy, _surf);
    if (_ctx != EGL_NO_CONTEXT) p_eglDestroyContext(_dpy, _ctx);
  }
  _surf = EGL_NO_SURFACE;
  _ctx = EGL_NO_CONTEXT;
  // (the view outlives the surface that drew into its layer)
  if (_view != NULL) {
    SDL_Metal_DestroyView(_view);
    _view = NULL;
  }
}

// An OpenGL ES 2.0 context (what gl4es is built for) on an EGL surface on
// SDL's Metal view of the window. 0 if the window was left untouched (Apple's
// OpenGL ES can still take it), -1 if not.
static int IOSGL_StartANGLE(SDL_Window *pWindow)
{
  const EGLint aContext[] = {
    EGL_CONTEXT_CLIENT_VERSION, 2,
    _bBackwardsCompat ? EGL_CONTEXT_OPENGL_BACKWARDS_COMPATIBLE_ANGLE : EGL_NONE, EGL_FALSE,
    EGL_NONE
  };
  _ctx = p_eglCreateContext(_dpy, _cfg, EGL_NO_CONTEXT, aContext);
  if (_ctx == EGL_NO_CONTEXT) return IOSGL_Fail("eglCreateContext failed");

  // (from here on the window is drawn by Metal, not by SDL's OpenGL ES)
  _view = SDL_Metal_CreateView(pWindow);
  void *pLayer = (_view != NULL) ? SDL_Metal_GetLayer(_view) : NULL;
  if (pLayer == NULL) {
    printf("iOS: graphics: ANGLE: no Metal view: %s\n", SDL_GetError());
    IOSGL_DestroyANGLE();
    return -1;
  }
  _surf = p_eglCreateWindowSurface(_dpy, _cfg, (EGLNativeWindowType) pLayer, NULL);
  if (_surf == EGL_NO_SURFACE || !p_eglMakeCurrent(_dpy, _surf, _surf, _ctx)) {
    IOSGL_Fail("no window surface");
    IOSGL_DestroyANGLE();
    return -1;
  }
  p_eglSwapInterval(_dpy, _iSwapInterval);
  return 1;
}

/* ---------------------------------------------------- the engine's calls */

SDL_GLContext IOS_GL_CreateContext(SDL_Window *pWindow)
{
  if (_iUsing == GL_NONE_YET) {
    if (IOSGL_LastStartFailed()) {
      printf("iOS: graphics: ANGLE didn't start last time: Apple's OpenGL ES this time\n");
      _iUsing = GL_APPLE;
    }
    else {
      _iUsing = IOSGL_ProbeANGLE() ? GL_ANGLE : GL_APPLE;
    }
  }
  if (_iUsing == GL_ANGLE) {
    IOSGL_DestroyANGLE();  // (a context made again)
    IOSGL_GuardBegin();
    const int iStarted = IOSGL_StartANGLE(pWindow);
    if (iStarted > 0) {
      EGLint w = 0, h = 0;
      p_eglQuerySurface(_dpy, _surf, EGL_WIDTH, &w);
      p_eglQuerySurface(_dpy, _surf, EGL_HEIGHT, &h);
      typedef const unsigned char *(*GetStringFn)(unsigned int);
      GetStringFn pGetString = (GetStringFn) IOS_GL_GetProcAddress("glGetString");
      printf("iOS: graphics: ANGLE (OpenGL ES on Metal): %s, %s, %dx%d\n",
             pGetString ? (const char *) pGetString(0x1F01) : "?",   // GL_RENDERER
             pGetString ? (const char *) pGetString(0x1F02) : "?",   // GL_VERSION
             (int) w, (int) h);
      fflush(stdout);
      return (SDL_GLContext) _ctx;
    }
    if (iStarted < 0) {
      // (the window is Metal's now: the next launch uses Apple's OpenGL ES)
      printf("iOS: graphics: ANGLE failed to start: Apple's OpenGL ES next launch\n");
      fflush(stdout);
      return NULL;
    }
    IOSGL_GuardEnd();
    _iUsing = GL_APPLE;
  }
  printf("iOS: graphics: Apple's OpenGL ES\n");
  fflush(stdout);
  return SDL_GL_CreateContext(pWindow);
}

int IOS_GL_MakeCurrent(SDL_Window *pWindow, SDL_GLContext pContext)
{
  if (_iUsing != GL_ANGLE) return SDL_GL_MakeCurrent(pWindow, pContext);
  if (_dpy == EGL_NO_DISPLAY) return -1;
  const EGLBoolean bOK = (pContext == NULL || _ctx == EGL_NO_CONTEXT)
    ? p_eglMakeCurrent(_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)
    : p_eglMakeCurrent(_dpy, _surf, _surf, _ctx);
  return bOK ? 0 : -1;
}

void IOS_GL_DeleteContext(SDL_GLContext pContext)
{
  if (_iUsing != GL_ANGLE) {
    SDL_GL_DeleteContext(pContext);
    return;
  }
  IOSGL_DestroyANGLE();
}

static void IOSGL_PerfFrame(uint64_t tSwap, uint64_t tDone);
static uint64_t IOSGL_FrameCap(void);
static uint64_t _tCapWait = 0;  // (the last wait in IOSGL_FrameCap, which the next frame's game time leaves out)
static uint64_t IOSGL_Ns(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ull + (uint64_t) ts.tv_nsec;
}

void IOS_GL_SwapWindow(SDL_Window *pWindow)
{
  const uint64_t tSwap = IOSGL_Ns();
  if (_iUsing != GL_ANGLE) {
    SDL_GL_SwapWindow(pWindow);
  }
  else if (_surf != EGL_NO_SURFACE) {
    static int bReported = 0;
    if (p_eglSwapBuffers(_dpy, _surf)) {
      if (_ctGuardFrames >= 0 && ++_ctGuardFrames >= IOSGL_GUARD_FRAMES) {
        IOSGL_GuardEnd();
        printf("iOS: graphics: ANGLE started (%d frames shown)\n", IOSGL_GUARD_FRAMES);
        fflush(stdout);
      }
    }
    else if (!bReported) {
      bReported = 1;
      IOSGL_Fail("eglSwapBuffers failed");
      fflush(stdout);
    }
  }
  IOSGL_PerfFrame(tSwap, IOSGL_Ns());
  _tCapWait = IOSGL_FrameCap();
}

// The tray's FPS at 60 on a 120 Hz screen: the screen is asked for 60, but
// the game's frames would still come at the screen's 120 (vsync), so they
// are kept at most 1/60 s apart here, after each swap (the waits save
// battery). Returns how long it waited.
extern int IOSTouch_MaxFps(void);
static uint64_t IOSGL_FrameCap(void)
{
  static uint64_t tNext = 0;
  const int iFps = IOSTouch_MaxFps();
  if (iFps <= 0 || iFps >= 120) {
    tNext = 0;
    return 0;
  }
  const uint64_t tPeriod = 1000000000ull / (uint64_t) iFps;
  const uint64_t tNow = IOSGL_Ns();
  // (far behind, after a pause or a load: from now on)
  if (tNext == 0 || tNow > tNext + tPeriod) tNext = tNow;
  uint64_t tWaited = 0;
  if (tNow < tNext) {
    const uint64_t tWait = tNext - tNow;
    struct timespec ts = { (time_t)(tWait / 1000000000ull), (long)(tWait % 1000000000ull) };
    nanosleep(&ts, NULL);
    tWaited = IOSGL_Ns() - tNow;
  }
  tNext += tPeriod;
  return tWaited;
}

int IOS_GL_SetSwapInterval(int iInterval)
{
  if (_iUsing != GL_ANGLE) return SDL_GL_SetSwapInterval(iInterval);
  _iSwapInterval = iInterval ? 1 : 0;
  if (_dpy == EGL_NO_DISPLAY) return 0;
  return p_eglSwapInterval(_dpy, _iSwapInterval) ? 0 : -1;
}

int IOS_GL_GetSwapInterval(void)
{
  if (_iUsing != GL_ANGLE) return SDL_GL_GetSwapInterval();
  return _iSwapInterval;
}

int IOS_GL_GetAttribute(SDL_GLattr eAttr, int *piValue)
{
  if (_iUsing == GL_ANGLE && _cfg != NULL && (eAttr == SDL_GL_DEPTH_SIZE || eAttr == SDL_GL_STENCIL_SIZE)) {
    EGLint i = 0;
    if (!p_eglGetConfigAttrib(_dpy, _cfg, (eAttr == SDL_GL_DEPTH_SIZE) ? EGL_DEPTH_SIZE : EGL_STENCIL_SIZE, &i)) return -1;
    *piValue = (int) i;
    return 0;
  }
  return SDL_GL_GetAttribute(eAttr, piValue);
}

// The size in pixels the frame is drawn at (what glReadPixels reads)
void IOS_GL_GetDrawableSize(SDL_Window *pWindow, int *piW, int *piH)
{
  if (_iUsing == GL_ANGLE && _surf != EGL_NO_SURFACE) {
    EGLint w = 0, h = 0;
    p_eglQuerySurface(_dpy, _surf, EGL_WIDTH, &w);
    p_eglQuerySurface(_dpy, _surf, EGL_HEIGHT, &h);
    if (piW) *piW = (int) w;
    if (piH) *piH = (int) h;
    return;
  }
  // (before ANGLE's surface: the window's size, which its Metal view gets)
  if (pWindow == NULL) pWindow = SDL_GL_GetCurrentWindow();
  if (pWindow == NULL) {
    if (piW) *piW = 0;
    if (piH) *piH = 0;
    return;
  }
  SDL_GL_GetDrawableSize(pWindow, piW, piH);
}

int IOS_GL_UsingANGLE(void)
{
  return _iUsing == GL_ANGLE;
}

/* -------------------------------------------- draw calls, for the log */

static int _ctDraws = 0;
static uint64_t _tInDraws = 0;
typedef void (*DrawArraysFn)(unsigned int, int, int);
typedef void (*DrawElementsFn)(unsigned int, int, unsigned int, const void *);
static DrawArraysFn _pDrawArrays = NULL;
static DrawElementsFn _pDrawElements = NULL;

static void IOSGL_DrawArrays(unsigned int eMode, int iFirst, int ctVertices)
{
  const uint64_t t0 = IOSGL_Ns();
  _pDrawArrays(eMode, iFirst, ctVertices);
  _tInDraws += IOSGL_Ns() - t0;
  _ctDraws++;
}

static void IOSGL_DrawElements(unsigned int eMode, int ctIndices, unsigned int eType, const void *pIndices)
{
  const uint64_t t0 = IOSGL_Ns();
  _pDrawElements(eMode, ctIndices, eType, pIndices);
  _tInDraws += IOSGL_Ns() - t0;
  _ctDraws++;
}

void *IOS_GL_GetProcAddress(const char *strName)
{
  void *p = NULL;
  if (_iUsing == GL_ANGLE) {
    p = (void *) p_eglGetProcAddress(strName);
  }
  else {
    if (_hAppleGLES == NULL) {
      _hAppleGLES = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY | RTLD_LOCAL);
    }
    p = _hAppleGLES ? dlsym(_hAppleGLES, strName) : NULL;
  }
  // (gl4es asks once for each: its draws go through these, which count them)
  if (p != NULL && strcmp(strName, "glDrawArrays") == 0) {
    _pDrawArrays = (DrawArraysFn) p;
    return (void *) IOSGL_DrawArrays;
  }
  if (p != NULL && strcmp(strName, "glDrawElements") == 0) {
    _pDrawElements = (DrawElementsFn) p;
    return (void *) IOSGL_DrawElements;
  }
  return p;
}

/* ------------------------------------------------------------ frame times */

// Every 5 seconds of play, into Output.log: the frames shown and where each
// one's time went: the game's own work (its ticks, sound, input, the
// overlay), drawing (the CPU handing OpenGL ES its work, through gl4es; and
// the part of that spent in the draw calls), presenting (the swap, which
// waits while the GPU or the screen is behind) and the wait that keeps to the
// tray's 60 FPS, and draw calls per frame
static uint64_t _tDrawStart = 0;
static int _bFrameInPlay = 0;

void IOS_PerfDrawStart(int bInPlay)
{
  _tDrawStart = IOSGL_Ns();
  _bFrameInPlay = bInPlay;
}

static void IOSGL_PerfFrame(uint64_t tSwap, uint64_t tDone)
{
  static uint64_t tLastDone = 0, tStart = 0, tGame = 0, tDraw = 0, tPresent = 0, tGL = 0, tWorst = 0, tCap = 0;
  static int ctFrames = 0, ctCalls = 0;
  const uint64_t tPrev = tLastDone;
  tLastDone = tDone;
  const int ctDraws = _ctDraws;
  const uint64_t tInDraws = _tInDraws;
  _ctDraws = 0;
  _tInDraws = 0;
  // (a frame of play: drawn after the last swap, by the game's main loop)
  const int bPlay = _bFrameInPlay && tPrev != 0 && _tDrawStart > tPrev && _tDrawStart <= tSwap;
  _bFrameInPlay = 0;
  if (!bPlay) {
    tStart = 0;
    return;
  }
  if (tStart == 0) {
    tStart = tPrev;
    ctFrames = ctCalls = 0;
    tGame = tDraw = tPresent = tGL = tWorst = tCap = 0;
  }
  ctFrames++;
  ctCalls += ctDraws;
  const uint64_t tCapped = (_tCapWait < _tDrawStart - tPrev) ? _tCapWait : _tDrawStart - tPrev;
  tCap += tCapped;
  tGame += _tDrawStart - tPrev - tCapped;
  tDraw += tSwap - _tDrawStart;
  tPresent += tDone - tSwap;
  tGL += tInDraws;
  if (tDone - tPrev > tWorst) tWorst = tDone - tPrev;
  if (tDone - tStart >= 5000000000ull) {
    const double ms = 1e-6 / ctFrames;
    printf("iOS: frames %.1f fps (%s); per frame %.1f ms (worst %.1f): game %.1f, drawing %.1f (in GL's draw calls %.1f), present %.1f, held to %d FPS %.1f; %d draw calls\n",
           ctFrames * 1e9 / (double)(tDone - tStart), (_iUsing == GL_ANGLE) ? "ANGLE" : "Apple's OpenGL ES",
           (double)(tDone - tStart) * ms, tWorst * 1e-6, tGame * ms, tDraw * ms, tGL * ms, tPresent * ms,
           IOSTouch_MaxFps(), tCap * ms, ctCalls / ctFrames);
    fflush(stdout);
    tStart = tDone;
    ctFrames = ctCalls = 0;
    tGame = tDraw = tPresent = tGL = tWorst = tCap = 0;
  }
}
