# Turns SeriousSam${MP} into an iOS .app bundle.
# Included from SamTFE/Sources and SamTSE/Sources CMakeLists.txt when IOS is set.
#
# Expects (passed on the command line by .github/workflows/ios.yml):
#   GL4ES_ROOT  - gl4es source tree with the iOS static library built in GL4ES_LIBRARY
#   SDL2_INCLUDE_DIR / SDL2_LIBRARY - SDL2 built for iOS

set(SE_IOS_DIR ${CMAKE_CURRENT_LIST_DIR})
set(SE_EXE SeriousSam${MP})

if(INTERNAL_NAME STREQUAL "serioussam")
  set(SE_IOS_NAME "Sam FE")
  set(SE_IOS_ID "io.github.sithewok13.serioussam.fe")
  set(SE_IOS_ICON "${CMAKE_CURRENT_SOURCE_DIR}/../serioussam.png")
else()
  set(SE_IOS_NAME "Sam SE")
  set(SE_IOS_ID "io.github.sithewok13.serioussam.se")
  set(SE_IOS_ICON "${CMAKE_CURRENT_SOURCE_DIR}/../serioussamse.png")
endif()
if(NOT SE_IOS_BUILD_NUMBER)
  set(SE_IOS_BUILD_NUMBER 1)
endif()

target_sources(${SE_EXE} PRIVATE ${SE_IOS_DIR}/IOSSupport.c)
target_include_directories(${SE_EXE} PRIVATE ${SDL2_INCLUDE_DIR})

# Touch controls: a UIKit overlay in Objective-C (ARC), and IOSTouch.h for the
# hooks in the engine, game and HUD (see patch_engine.py)
enable_language(OBJC)
target_sources(${SE_EXE} PRIVATE ${SE_IOS_DIR}/IOSTouch.m)
set_source_files_properties(${SE_IOS_DIR}/IOSTouch.m PROPERTIES COMPILE_OPTIONS "-fobjc-arc;-fno-ms-extensions")
foreach(_target ${ENGINELIB} ${GAMEMPLIB} ${ENTITIESMPLIB} ${SE_EXE})
  target_include_directories(${_target} PRIVATE ${SE_IOS_DIR})
endforeach()
target_include_directories(${ENGINELIB} PRIVATE ${GL4ES_ROOT}/include)

set_target_properties(${SE_EXE} PROPERTIES
  MACOSX_BUNDLE TRUE
  MACOSX_BUNDLE_INFO_PLIST ${SE_IOS_DIR}/Info.plist.in
  MACOSX_BUNDLE_GUI_IDENTIFIER ${SE_IOS_ID}
  MACOSX_BUNDLE_BUNDLE_NAME ${SE_IOS_NAME}
  MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.${SE_IOS_BUILD_NUMBER}"
  MACOSX_BUNDLE_BUNDLE_VERSION ${SE_IOS_BUILD_NUMBER}
  XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
)

# SDL2main supplies main() on iOS (starts UIKit, then calls our SDL_main)
get_filename_component(SE_SDL2_LIBDIR ${SDL2_LIBRARY} DIRECTORY)

target_link_libraries(${SE_EXE}
  ${SE_SDL2_LIBDIR}/libSDL2main.a
  ${GL4ES_LIBRARY}
  "-framework Foundation"
  "-framework UIKit"
  "-framework OpenGLES"
  "-framework QuartzCore"
  "-framework CoreGraphics"
  "-framework CoreVideo"
  "-framework CoreMotion"
  "-framework CoreAudio"
  "-framework AudioToolbox"
  "-framework AVFoundation"
  "-framework GameController"
  "-framework Metal"
  "-weak_framework CoreHaptics"
  "-weak_framework UniformTypeIdentifiers"
  iconv
)

# Files the engine needs next to the game data (part of the open-source
# release, not Croteam's game content) plus the home-screen icon.
add_custom_command(TARGET ${SE_EXE} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
          ${CMAKE_CURRENT_SOURCE_DIR}/../SE1_10b.gro
          ${CMAKE_CURRENT_SOURCE_DIR}/../ModEXT.txt
          $<TARGET_BUNDLE_DIR:${SE_EXE}>/
  COMMAND sips -z 120 120 ${SE_IOS_ICON} --out $<TARGET_BUNDLE_DIR:${SE_EXE}>/AppIcon60x60@2x.png
  COMMAND sips -z 180 180 ${SE_IOS_ICON} --out $<TARGET_BUNDLE_DIR:${SE_EXE}>/AppIcon60x60@3x.png
  VERBATIM
)
