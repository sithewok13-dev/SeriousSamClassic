/* Copyright (c) 2002-2012 Croteam Ltd. All rights reserved. */

#include <Engine/Engine.h>
#include "SDL.h"

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

static void FailFunction_t(const char *strName) {
  ThrowF_t(TRANS("Required function %s not found."), strName);
}

static void sdlCheckError(BOOL bRes, const char *strDescription)
{
  if( bRes) return;
  const char *sdlError = SDL_GetError();
  if( !sdlError) return; // ignore stupid 'successful' error
  WarningMessage("%s: %s", strDescription, sdlError);
}

static void OGL_SetFunctionPointers_t(HINSTANCE hiOGL)
{
  const char *strName;
  // get gl function pointers

  #define DLLFUNCTION(dll, output, name, inputs, params, required) \
    strName = #name;  \
    p##name = (output (__stdcall*) inputs) SE_GL_GETPROC(strName); \
    if( required && p##name == NULL) FailFunction_t(strName);
  #include "Engine/Graphics/gl_functions.h"
  #undef DLLFUNCTION
}

BOOL CGfxLibrary::InitDriver_OGL(BOOL init3dfx)
{
  ASSERT( gl_hiDriver==NONE);  // this is managed inside SDL, so we never load a library ourselves.

  if (SDL_GL_LoadLibrary(NULL) == -1) {
    sdlCheckError(0, "Failed to load OpenGL API");
    return FALSE;
  }

  // done
  return TRUE;
}


void CGfxLibrary::PlatformEndDriver_OGL(void)
{
  // shut the driver down
  SDL_GL_MakeCurrent(NULL, NULL);
  if (go_hglRC) {
    SDL_GL_DeleteContext(go_hglRC);
    go_hglRC = NULL;
  }
}

// creates OpenGL drawing context
BOOL CGfxLibrary::CreateContext_OGL(HDC hdc)
{
  SDL_Window *window = (SDL_Window *) hdc;
  if( !SetupPixelFormat_OGL( hdc, TRUE)) return FALSE;
  go_hglRC = SDL_GL_CreateContext(window);
  if( go_hglRC==NULL) {
    sdlCheckError(0, "OpenGL context creation");
    return FALSE;
  }
  if (SDL_GL_MakeCurrent(window, go_hglRC) == -1) {
    // NOTE: This error is sometimes reported without a reason on 3dfx hardware
    // so we just have to ignore it.
    sdlCheckError(0, "MakeCurrent after CreateContext");
    return FALSE;
  }
  int val = 0;
  if (SDL_GL_GetAttribute(SDL_GL_DEPTH_SIZE, &val) != -1) {  // keep depth bits
    gl_iCurrentDepth = val;
  } else {
    gl_iCurrentDepth = 16;  // oh well.
  }

#ifdef PLATFORM_IOS
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
#ifdef PLATFORM_IOS
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
      printf("GLES: %s, %s\n", pGetString(0x1F01), pGetString(0x1F02));  // GL_RENDERER, GL_VERSION
      printf("GLES: depth %d bits, stencil %d bits, framebuffer %d, drawable %dx%d\n",
             iDepth, iStencil, iFBO, iW, iH);
      printf("GLES extensions: %s\n", pGetString(0x1F03));  // GL_EXTENSIONS
    }
  }
#endif
  // prepare functions
  OGL_SetFunctionPointers_t(gl_hiDriver);

  return TRUE;
}

void *CGfxLibrary::OGL_GetProcAddress(const char *procname)
{
    return(SE_GL_GETPROC(procname));
}

// prepares pixel format for OpenGL context
BOOL CGfxLibrary::SetupPixelFormat_OGL( HDC hdc, BOOL bReport/*=FALSE*/)
{
  //SDL_Window *window = (SDL_Window *) hdc;
  const DisplayDepth dd  = gl_dmCurrentDisplayMode.dm_ddDepth;

  // clamp depth/stencil values
  extern INDEX gap_iDepthBits;
  extern INDEX gap_iStencilBits;
       if( gap_iDepthBits <22) gap_iDepthBits   = 16; // this includes 0; 16 is a safe default
  else if( gap_iDepthBits <28) gap_iDepthBits   = 24;
  else                         gap_iDepthBits   = 32;
       if( gap_iStencilBits<3) gap_iStencilBits = 0;
  else if( gap_iStencilBits<7) gap_iStencilBits = 4;
  else                         gap_iStencilBits = 8;

  SDL_GL_SetAttribute(SDL_GL_RED_SIZE, (dd != DD_16BIT) ? 8 : 5);
  SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, (dd != DD_16BIT) ? 8 : 6);
  SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, (dd != DD_16BIT) ? 8 : 5);
  SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 0);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
#ifdef PLATFORM_IOS
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
#endif
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, gap_iDepthBits);
  SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, gap_iStencilBits);

  STUBBED("co-opt the existing T-buffer support for multisampling?");
  //SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, x);
  //SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, y);

  return TRUE;
}

// prepare current viewport for rendering thru OpenGL
BOOL CGfxLibrary::SetCurrentViewport_OGL(CViewPort *pvp)
{
  // if must init entire opengl
  if( gl_ulFlags & GLF_INITONNEXTWINDOW)
  {
    gl_ulFlags &= ~GLF_INITONNEXTWINDOW;
    // reopen window
    pvp->CloseCanvas();
    pvp->OpenCanvas();
    // init now
    if( !CreateContext_OGL((HDC) pvp->vp_hWnd)) return FALSE;
    gl_pvpActive = pvp; // remember as current viewport (must do that BEFORE InitContext)
    InitContext_OGL();
    gl_ulFlags |=  GLF_HASACCELERATION;  // !!! FIXME: might be a lie, though...
    pvp->vp_ctDisplayChanges = gl_ctDriverChanges;
    return TRUE;
  }

  // if window was not set for this driver
  if( pvp->vp_ctDisplayChanges<gl_ctDriverChanges)
  {
    // reopen window
    pvp->CloseCanvas();
    pvp->OpenCanvas();

    // set it
    pvp->vp_ctDisplayChanges = gl_ctDriverChanges;
  }

  // remember as current window
  gl_pvpActive = pvp;
  return TRUE;
}

// end of SDLOpenGL.cpp ...


