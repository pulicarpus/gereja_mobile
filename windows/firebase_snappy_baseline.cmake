# Firebase C++ SDK 12.7.0 ships Snappy built with BMI2 (BZHI). It crashes on
# processors such as the Celeron N4500 when Firestore decompresses stored data.
# Compiler flags on the runner cannot change those precompiled objects.
function(gkii_use_baseline_snappy)
  if(NOT MSVC)
    message(FATAL_ERROR "Windows Firebase baseline replacement requires MSVC")
  endif()
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  set(replacement_count 0)
  foreach(sdk_target firebase_app firebase_auth firebase_storage firebase_firestore)
    foreach(config DEBUG RELEASE)
      get_target_property(original ${sdk_target} IMPORTED_LOCATION_${config})
      if(NOT original OR NOT EXISTS "${original}")
        message(FATAL_ERROR "Missing Firebase archive: ${sdk_target}/${config}")
      endif()
      set(replacement "${CMAKE_BINARY_DIR}/baseline-sdk/${sdk_target}-${config}.lib")
      execute_process(
        COMMAND "${Python3_EXECUTABLE}"
          "${CMAKE_CURRENT_SOURCE_DIR}/../tool/firebase_snappy_baseline.py"
          --lib-tool "${CMAKE_AR}" --input "${original}" --output "${replacement}"
        RESULT_VARIABLE result OUTPUT_VARIABLE outcome ERROR_VARIABLE errors
        OUTPUT_STRIP_TRAILING_WHITESPACE)
      if(NOT result EQUAL 0)
        message(FATAL_ERROR "Firebase Snappy replacement failed: ${outcome} ${errors}")
      endif()
      if(outcome STREQUAL "UPDATED")
        set_target_properties(${sdk_target} PROPERTIES
          IMPORTED_LOCATION_${config} "${replacement}")
        if(config STREQUAL "RELEASE")
          set_target_properties(${sdk_target} PROPERTIES
            IMPORTED_LOCATION "${replacement}"
            IMPORTED_LOCATION_PROFILE "${replacement}"
            MAP_IMPORTED_CONFIG_PROFILE RELEASE)
        endif()
        math(EXPR replacement_count "${replacement_count} + 1")
      endif()
    endforeach()
  endforeach()
  if(replacement_count EQUAL 0)
    message(FATAL_ERROR "Firebase SDK layout changed; review Snappy replacement before building")
  endif()

  include(FetchContent)
  # Same stable Snappy 1.1 API and wire format as Firebase's bundled 1.1.9.
  # 1.1.10 also fixes the MSVC inline declaration patched by Firebase upstream.
  set(SNAPPY_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(SNAPPY_BUILD_BENCHMARKS OFF CACHE BOOL "" FORCE)
  set(SNAPPY_INSTALL OFF CACHE BOOL "" FORCE)
  set(SNAPPY_REQUIRE_AVX OFF CACHE BOOL "" FORCE)
  set(SNAPPY_REQUIRE_AVX2 OFF CACHE BOOL "" FORCE)
  # Compilation of an intrinsic does not prove the user's CPU supports it.
  set(SNAPPY_HAVE_BMI2 OFF CACHE BOOL "" FORCE)
  set(SNAPPY_HAVE_SSSE3 OFF CACHE BOOL "" FORCE)
  set(SNAPPY_HAVE_X86_CRC32 OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(gkii_snappy
    URL https://github.com/google/snappy/archive/refs/tags/1.1.10.tar.gz
    URL_HASH SHA256=49d831bffcc5f3d01482340fe5af59852ca2fe76c3e05df0e67203ebbe0f1d90)
  FetchContent_MakeAvailable(gkii_snappy)
  # Firebase renames bundled dependency namespaces to avoid collisions.
  # Match its binary ABI, including LevelDB's f_b_snappy references.
  target_compile_definitions(snappy PUBLIC snappy=f_b_snappy)
  target_compile_definitions(snappy PRIVATE
    SNAPPY_HAVE_BMI2=0 SNAPPY_HAVE_SSSE3=0 SNAPPY_HAVE_X86_CRC32=0)
  target_link_libraries(${BINARY_NAME} PRIVATE snappy)
  install(FILES "${gkii_snappy_SOURCE_DIR}/COPYING"
    DESTINATION "${CMAKE_INSTALL_PREFIX}" RENAME "SNAPPY-LICENSE.txt")

  add_executable(gkii_snappy_test "../test/native/snappy_baseline_test.cpp")
  target_link_libraries(gkii_snappy_test PRIVATE snappy)
  set_target_properties(gkii_snappy_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/native-tests")
  add_dependencies(${BINARY_NAME} gkii_snappy_test)
endfunction()
