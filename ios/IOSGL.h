/* The OpenGL ES that gl4es draws with on iOS (IOSGL.c).
 *
 * ANGLE first: OpenGL ES 2.0 on Metal, drawing into an SDL Metal view, as
 * the owner's other ports do. Apple's own OpenGL ES (through SDL's EAGL
 * view) is deprecated and costs a lot of CPU time per draw call. If ANGLE
 * can't start (it isn't in the app, it fails to set up, or the last launch
 * stopped while it was starting), Apple's OpenGL ES runs instead, as before.
 * Output.log says which one runs.
 *
 * Included by the engine's SDL OpenGL code (SDLOpenGL.cpp, GfxLibrary.cpp):
 * there the SDL_GL_* calls below become these, so the engine's own code stays
 * as it is. Also logs frame times (every 5 seconds of play) and keeps the
 * frames to the tray's 60 FPS (IOSTouch_MaxFps).
 */
#ifndef IOSGL_H
#define IOSGL_H

#include <SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

SDL_GLContext IOS_GL_CreateContext(SDL_Window *pWindow);
int           IOS_GL_MakeCurrent(SDL_Window *pWindow, SDL_GLContext pContext);
void          IOS_GL_DeleteContext(SDL_GLContext pContext);
void          IOS_GL_SwapWindow(SDL_Window *pWindow);
int           IOS_GL_SetSwapInterval(int iInterval);
int           IOS_GL_GetSwapInterval(void);
int           IOS_GL_GetAttribute(SDL_GLattr eAttr, int *piValue);
void          IOS_GL_GetDrawableSize(SDL_Window *pWindow, int *piW, int *piH);
// The real OpenGL ES entry points (not gl4es' own glXxx in this binary)
void         *IOS_GL_GetProcAddress(const char *strName);
// 1 while ANGLE draws, 0 for Apple's OpenGL ES (or nothing chosen yet)
int           IOS_GL_UsingANGLE(void);

// Frame times: the game calls this when it starts drawing a frame (1 if the
// frame is one of play, which is what gets logged); the swap ends the frame.
void          IOS_PerfDrawStart(int bInPlay);

#ifdef __cplusplus
}
#endif

#ifndef IOSGL_IMPLEMENTATION
#define SDL_GL_CreateContext    IOS_GL_CreateContext
#define SDL_GL_MakeCurrent      IOS_GL_MakeCurrent
#define SDL_GL_DeleteContext    IOS_GL_DeleteContext
#define SDL_GL_SwapWindow       IOS_GL_SwapWindow
#define SDL_GL_SetSwapInterval  IOS_GL_SetSwapInterval
#define SDL_GL_GetSwapInterval  IOS_GL_GetSwapInterval
#define SDL_GL_GetAttribute     IOS_GL_GetAttribute
#define SDL_GL_GetDrawableSize  IOS_GL_GetDrawableSize
#endif

#endif /* IOSGL_H */
