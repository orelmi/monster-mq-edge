# WinCC OA API manager embedding the MonsterMQ Edge broker.
#
# Build (developer-run, see README.md):
#   Linux:
#     export API_ROOT=/opt/WinCC_OA/3.21/api
#     make -C ../.. embed-lib            # builds ../../build/embed/libmonstermq.a
#     mkdir build && cd build && cmake .. && make
#   Windows (x64 Native Tools Command Prompt for VS 2022), or winccoa\build.bat:
#     set API_ROOT=C:\Siemens\Automation\WinCC_OA\3.21\api
#     make embed-dll                     # MSYS2 UCRT64 shell: ../../build/embed-windows/monstermq.dll
#     cmake -S . -B build -G "Visual Studio 17 2022" -A x64
#     cmake --build build --config Release
cmake_minimum_required(VERSION 3.21.1)

set(API_ROOT_ENV "$ENV{API_ROOT}" CACHE FILEPATH "directory of the WinCC_OA API installation")
string(REPLACE "\"" "" API_ROOT "${API_ROOT_ENV}")
file(TO_CMAKE_PATH "${API_ROOT}" API_ROOT)

include(${API_ROOT}/CMakeDefines.txt)

project(monstermq)

set(TARGET WCCOAmmq)

if(WIN32)
  set(MMQ_EMBED_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../build/embed-windows")
else()
  set(MMQ_EMBED_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../build/embed")
endif()
set(MMQ_EMBED_DIR "${MMQ_EMBED_DEFAULT}" CACHE PATH "directory with libmonstermq.a (Linux) or monstermq.dll and monstermq.def (Windows), and monstermq.h")

set(SOURCES
  MonsterMQMain.cxx
  MonsterMQManager.cxx
  MonsterMQProbe.cxx
  MonsterMQResources.cxx
  MmqPlatform.cxx
  MmqTlv.cxx
)

add_manager(${TARGET} ${SOURCES})
target_include_directories(${TARGET} PRIVATE ${MMQ_EMBED_DIR})

if(WIN32)
  # cgo cannot build with MSVC: monstermq.dll comes from mingw-w64
  # (make embed-dll) and is linked through an MSVC import library made from
  # monstermq.def. Its C ABI passes no CRT object across the boundary.
  get_filename_component(MMQ_MSVC_BIN "${CMAKE_LINKER}" DIRECTORY)
  find_program(MMQ_LIB_EXE lib HINTS "${MMQ_MSVC_BIN}" REQUIRED)
  set(MMQ_IMPLIB "${CMAKE_CURRENT_BINARY_DIR}/monstermq.lib")
  add_custom_command(
    OUTPUT "${MMQ_IMPLIB}"
    COMMAND "${MMQ_LIB_EXE}" /nologo /machine:x64 "/def:${MMQ_EMBED_DIR}/monstermq.def" "/out:${MMQ_IMPLIB}"
    DEPENDS "${MMQ_EMBED_DIR}/monstermq.def"
    COMMENT "Import library for monstermq.dll")
  add_custom_target(monstermq_implib DEPENDS "${MMQ_IMPLIB}")
  add_dependencies(${TARGET} monstermq_implib)
  target_link_libraries(${TARGET} "${MMQ_IMPLIB}" winmm)
  # The DLL is loaded from the directory of WCCOAmmq.exe.
  add_custom_command(TARGET ${TARGET} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${MMQ_EMBED_DIR}/monstermq.dll" "$<TARGET_FILE_DIR:${TARGET}>")
else()
  # The Go c-archive needs pthread and dl; it is linked last.
  target_link_libraries(${TARGET} ${MMQ_EMBED_DIR}/libmonstermq.a pthread dl)
endif()
