#!/usr/bin/env python3
"""One-off helper used to add the static/iOS build mode to both games'
CMakeLists.txt. Kept for reference; it is idempotent."""
import re, sys, pathlib

MARK = "# >>> SE_STATIC (iOS port)"

HEAD = f"""
{MARK}
# Link Engine, Game, Entities, Shaders and decoders into one executable.
# Required on iOS (no loading of our own shared libraries at runtime).
if(IOS)
  set(SE_STATIC_DEFAULT ON)
else()
  set(SE_STATIC_DEFAULT OFF)
endif()
option(SE_STATIC "Statically link all game modules into the executable" ${{SE_STATIC_DEFAULT}})
if(SE_STATIC)
  set(SE_LIBTYPE STATIC)
  add_definitions(-DSTATICALLY_LINKED=1)
  include_directories(${{CMAKE_CURRENT_SOURCE_DIR}}/../../ios/include)  # bundled ogg config
else()
  set(SE_LIBTYPE SHARED)
endif()
if(IOS)
  add_definitions(-DPLATFORM_IOS=1)
endif()
# <<< SE_STATIC
"""

TAIL = f"""
{MARK}
if(SE_STATIC AND NOT XPLUS)
  # ogg/vorbis decoders, normally loaded at runtime from the system
  set(SE_VORBIS_DIR ${{CMAKE_CURRENT_SOURCE_DIR}}/External/libvorbis/lib)
  set(SE_OGG_DIR ${{CMAKE_CURRENT_SOURCE_DIR}}/External/libogg/src)
  add_library(se_vorbis${{MP}} STATIC
    ${{SE_OGG_DIR}}/bitwise.c ${{SE_OGG_DIR}}/framing.c
    ${{SE_VORBIS_DIR}}/analysis.c ${{SE_VORBIS_DIR}}/bitrate.c ${{SE_VORBIS_DIR}}/block.c
    ${{SE_VORBIS_DIR}}/codebook.c ${{SE_VORBIS_DIR}}/envelope.c ${{SE_VORBIS_DIR}}/floor0.c
    ${{SE_VORBIS_DIR}}/floor1.c ${{SE_VORBIS_DIR}}/info.c ${{SE_VORBIS_DIR}}/lookup.c
    ${{SE_VORBIS_DIR}}/lpc.c ${{SE_VORBIS_DIR}}/lsp.c ${{SE_VORBIS_DIR}}/mapping0.c
    ${{SE_VORBIS_DIR}}/mdct.c ${{SE_VORBIS_DIR}}/psy.c ${{SE_VORBIS_DIR}}/registry.c
    ${{SE_VORBIS_DIR}}/res0.c ${{SE_VORBIS_DIR}}/sharedbook.c ${{SE_VORBIS_DIR}}/smallft.c
    ${{SE_VORBIS_DIR}}/synthesis.c ${{SE_VORBIS_DIR}}/vorbisfile.c ${{SE_VORBIS_DIR}}/window.c
  )
  target_include_directories(se_vorbis${{MP}} PRIVATE
    ${{CMAKE_CURRENT_SOURCE_DIR}}/../../ios/include
    ${{CMAKE_CURRENT_SOURCE_DIR}}/External/libogg/include
    ${{CMAKE_CURRENT_SOURCE_DIR}}/External/libvorbis/include
    ${{SE_VORBIS_DIR}})
  target_compile_options(se_vorbis${{MP}} PRIVATE -w)

  # Everything is looked up by name at runtime (entity classes, GAME_Create,
  # shaders, decoder functions), so keep every object file.
  set(SE_WHOLE ${{ENGINELIB}} ${{ENTITIESMPLIB}} ${{GAMEMPLIB}} ${{SHADERSLIB}} se_vorbis${{MP}})
  if(BUILD_AMP11LIB)
    list(APPEND SE_WHOLE amp11lib${{MP}})
  endif()
  foreach(_lib ${{SE_WHOLE}})
    target_link_libraries(SeriousSam${{MP}} "$<LINK_LIBRARY:WHOLE_ARCHIVE,${{_lib}}>")
  endforeach()
  target_link_libraries(SeriousSam${{MP}} engine_safemath${{MP}} ${{SDL2_LIBRARY}} ${{ZLIB_LIBRARIES}})
  if(NOT APPLE)
    target_link_libraries(SeriousSam${{MP}} m dl pthread)
  endif()
endif()

if(IOS AND NOT XPLUS)
  include(${{CMAKE_CURRENT_SOURCE_DIR}}/../../ios/ios_app.cmake)
endif()
# <<< SE_STATIC
"""

def patch(path: pathlib.Path):
    s = path.read_text()
    if MARK in s:
        print(f"{path}: already patched"); return
    # 1. option block right after the game name definition
    s = s.replace('option(TFE "Compile a The First Encounter version" FALSE)\n',
                  'option(TFE "Compile a The First Encounter version" FALSE)\n' + HEAD, 1)
    assert MARK in s, "anchor for HEAD not found"
    # 2. library type
    s, n = re.subn(r'add_library\((\$\{(?:ENTITIESMPLIB|GAMEMPLIB|SHADERSLIB|ENGINELIB)\}|amp11lib\$\{MP\}) SHARED',
                   r'add_library(\1 ${SE_LIBTYPE}', s)
    assert n == 6, n
    # 3. no "-undefined dynamic_lookup" for static archives
    s, n = re.subn(r'if\(MACOSX\)\n(\s*target_link_libraries\([^\n]*"-undefined dynamic_lookup"\))',
                   r'if(MACOSX AND NOT SE_STATIC)\n\1', s)
    assert n == 4, n
    # 4. macOS desktop-only link blocks (local Cocoa SDL dylib etc.)
    s = s.replace('if(MACOSX)\n    if(USE_SYSTEM_SDL2) # use sdl2 framework on system\n      target_link_libraries(${ENGINELIB}',
                  'if(MACOSX AND NOT SE_STATIC)\n    if(USE_SYSTEM_SDL2) # use sdl2 framework on system\n      target_link_libraries(${ENGINELIB}')
    s = s.replace('if(MACOSX)\n    target_link_libraries(SeriousSam${MP} ${ZLIB_LIBRARIES})',
                  'if(MACOSX AND NOT SE_STATIC)\n    target_link_libraries(SeriousSam${MP} ${ZLIB_LIBRARIES})')
    # Linux: static build does its own linking (avoids linking libEngine twice)
    s = s.replace('if(LINUX)\n    set_target_properties(SeriousSam${MP} PROPERTIES LINK_FLAGS "-Wl,${RPATH_SETTINGS}")\n    target_link_libraries(SeriousSam${MP} "m")',
                  'if(LINUX AND NOT SE_STATIC)\n    set_target_properties(SeriousSam${MP} PROPERTIES LINK_FLAGS "-Wl,${RPATH_SETTINGS}")\n    target_link_libraries(SeriousSam${MP} "m")')
    # the executable links the engine whole-archive itself in static mode
    s = s.replace('target_link_libraries(SeriousSam${MP} ${ENGINELIB})',
                  'if(NOT SE_STATIC)\n  target_link_libraries(SeriousSam${MP} ${ENGINELIB})\nendif()', 1)
    # 5. host-arm flags block must not apply when cross-compiling for iOS
    s = s.replace('if(NOT PYRA AND NOT PANDORA AND ${CMAKE_HOST_SYSTEM_PROCESSOR} MATCHES "arm*")',
                  'if(NOT IOS AND NOT PYRA AND NOT PANDORA AND ${CMAKE_HOST_SYSTEM_PROCESSOR} MATCHES "arm*")')
    s = s.replace('if(NOT PANDORA AND NOT PYRA AND NOT RPI4 AND NOT (MACOSX AND CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64"))',
                  'if(NOT IOS AND NOT PANDORA AND NOT PYRA AND NOT RPI4 AND NOT (MACOSX AND CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64"))')
    # 6. prebuilt host ECC for the Second Encounter build
    s = s.replace('    set(ECC-SE "ecc-se")\nendif()',
                  '    set(ECC-SE "ecc-se")\nelseif(NOT ECC-SE)\n    set(ECC-SE "${ECC}")\nendif()')
    # 7. append tail before the install section
    s = s.replace('# RAKE! Install Section.', TAIL + '\n# RAKE! Install Section.', 1)
    # 8. no desktop install rules for the iOS app bundle
    s = s.replace('if(LOCAL_INSTALL AND NOT XPLUS)\nif(DEBUG)',
                  'if(IOS)\n  # app bundle is packaged by ios/ios_app.cmake\nelseif(LOCAL_INSTALL AND NOT XPLUS)\nif(DEBUG)', 1)
    s = s.replace('if(NOT LOCAL_INSTALL AND NOT XPLUS)\n    install(FILES',
                  'if(NOT IOS AND NOT LOCAL_INSTALL AND NOT XPLUS)\n    install(FILES', 1)
    # 9. tools are optional
    s = re.sub(r'^ set_target_properties\(((?:DedicatedServer|MakeFONT|TEXConv)\$\{MP\})(\s+PROPERTIES OUTPUT_NAME [^\n]*\))$',
               r' if(TARGET \1)\n  set_target_properties(\1\2\n endif()', s, flags=re.M)
    s = s.replace('    \t\tinclude_directories("/usr/local/include")\n\t\tinclude_directories("/usr/X11/include/")\n',
                  '    \t\tif(NOT IOS)  # host headers must not leak into the iOS build\n    \t\t  include_directories("/usr/local/include")\n\t\t  include_directories("/usr/X11/include/")\n    \t\tendif()\n', 1)
    assert s.count(MARK) == 2
    path.write_text(s)
    print(f"{path}: patched")

for p in sys.argv[1:]:
    patch(pathlib.Path(p))
