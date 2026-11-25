# eden - ReXGlue Recompiled Project
#
# The SDK package provides rexglue_project and the rexglue_setup_* functions.

cmake_minimum_required(VERSION 3.25)
project(eden LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if (REXSDK_DIR)
  add_subdirectory("${REXSDK_DIR}" rexglue-sdk)
else ()
  find_package(rexglue 0.11.0 REQUIRED CONFIG)
endif ()
rexglue_project(eden OUTPUT_DIR generated/default)

# Host sources. src/main.cpp stays on the executable.
set(EDEN_HOST_SOURCES src/eden_hooks.cpp)

# OBJECT and never STATIC, an archive drops the REX_EXPORT symbols.
add_library(eden_common OBJECT ${EDEN_HOST_SOURCES})
rexglue_setup_host_library(eden_common)

if (WIN32)
  add_executable(eden WIN32 src/main.cpp)
else ()
  add_executable(eden src/main.cpp)
endif ()

rexglue_setup_target(eden)
target_link_libraries(eden PRIVATE eden_common)
