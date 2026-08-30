cmake_minimum_required(VERSION 3.24)

project(ecg_wfdb_io LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Place binaries in a predictable location regardless of generator.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# ---------------------------------------------------------------------------
# Warnings
# ---------------------------------------------------------------------------
add_library(project_warnings INTERFACE)
if(MSVC)
  target_compile_options(project_warnings INTERFACE /W4 /permissive-)
else()
  target_compile_options(project_warnings INTERFACE
    -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion)
endif()

# ---------------------------------------------------------------------------
# WFDB input/output library
# ---------------------------------------------------------------------------
add_library(wfdb_io
  src/header.cpp
  src/signal_reader.cpp
  src/annotation.cpp
)
target_include_directories(wfdb_io PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(wfdb_io PRIVATE project_warnings)

# ---------------------------------------------------------------------------
# Command-line inspection tool
# ---------------------------------------------------------------------------
add_executable(wfdb_info tools/wfdb_info.cpp)
target_link_libraries(wfdb_info PRIVATE wfdb_io project_warnings)

# ---------------------------------------------------------------------------
# Command-line annotation summary tool
# ---------------------------------------------------------------------------
add_executable(wfdb_ann tools/wfdb_ann.cpp)
target_link_libraries(wfdb_ann PRIVATE wfdb_io project_warnings)

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
option(BUILD_TESTING_WFDB "Build the unit tests" ON)

if(BUILD_TESTING_WFDB)
  include(FetchContent)
  FetchContent_Declare(googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.15.2
  )
  # Link against the same C runtime as the rest of the project on Windows.
  set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(googletest)

  enable_testing()

  add_executable(wfdb_tests
    tests/test_header.cpp
    tests/test_signal_reader.cpp
    tests/test_annotation.cpp
  )
  target_link_libraries(wfdb_tests
    PRIVATE wfdb_io project_warnings GTest::gtest_main)

  # Absolute paths to the MIT-BIH files and the reference fixture so the tests
  # can find them from any working directory. Tests that need either one skip
  # themselves when it is absent.
  target_compile_definitions(wfdb_tests PRIVATE
    WFDB_TEST_DATA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../data/mitdb"
    WFDB_TEST_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/data")

  include(GoogleTest)
  gtest_discover_tests(wfdb_tests)
endif()