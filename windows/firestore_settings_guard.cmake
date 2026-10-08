# Patch a build-local copy, preserving the installed FlutterFire package.
function(gkii_guard_firestore_settings)
  get_target_property(sources cloud_firestore_plugin SOURCES)
  get_target_property(source_dir cloud_firestore_plugin SOURCE_DIR)
  set(found 0)
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/../tool/patch_windows_firestore.py")
  set(patched_sources "")
  foreach(source IN LISTS sources)
    if(source MATCHES "(^|/)(cloud_firestore_plugin|firestore_codec)\\.cpp$")
      if(IS_ABSOLUTE "${source}")
        set(original "${source}")
      else()
        set(original "${source_dir}/${source}")
      endif()
      set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${original}")
      get_filename_component(filename "${original}" NAME)
      set(patched "${CMAKE_BINARY_DIR}/gkii-firestore/${filename}")
      file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/gkii-firestore")
      execute_process(COMMAND "${Python3_EXECUTABLE}"
        "${CMAKE_CURRENT_SOURCE_DIR}/../tool/patch_windows_firestore.py"
        "${original}" "${patched}" RESULT_VARIABLE status)
      if(NOT status EQUAL 0)
        message(FATAL_ERROR "FlutterFire Windows settings implementation changed; review guard")
      endif()
      list(APPEND patched_sources "${patched}")
      math(EXPR found "${found} + 1")
    else()
      # Preserve relative plugin paths when assigning SOURCES from our directory.
      if(IS_ABSOLUTE "${source}" OR source MATCHES "^\\$<")
        list(APPEND patched_sources "${source}")
      else()
        list(APPEND patched_sources "${source_dir}/${source}")
      endif()
    endif()
  endforeach()
  if(NOT found EQUAL 2)
    message(FATAL_ERROR "Both FlutterFire Windows instance creation paths must be patched")
  endif()
  set_target_properties(cloud_firestore_plugin PROPERTIES SOURCES "${patched_sources}")
  target_include_directories(cloud_firestore_plugin PRIVATE
    "${source_dir}" "${CMAKE_CURRENT_SOURCE_DIR}")

  add_executable(gkii_firestore_settings_test "../test/native/firestore_settings_test.cpp")
  target_include_directories(gkii_firestore_settings_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
  target_link_libraries(gkii_firestore_settings_test PRIVATE firebase_app firebase_auth firebase_firestore snappy
    advapi32 ws2_32 crypt32 rpcrt4 ole32 icu shell32 bcrypt dbghelp)
  set_target_properties(gkii_firestore_settings_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/native-tests")
  add_dependencies(${BINARY_NAME} gkii_firestore_settings_test)

  add_executable(gkii_firestore_codec_test "../test/native/firestore_codec_test.cpp")
  target_include_directories(gkii_firestore_codec_test PRIVATE
    "${source_dir}" "${CMAKE_CURRENT_SOURCE_DIR}")
  target_link_libraries(gkii_firestore_codec_test PRIVATE cloud_firestore_plugin
    flutter_wrapper_plugin firebase_core_plugin firebase_app firebase_auth firebase_firestore snappy
    advapi32 ws2_32 crypt32 rpcrt4 ole32 icu shell32 bcrypt dbghelp)
  set_target_properties(gkii_firestore_codec_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/native-tests")
  add_dependencies(${BINARY_NAME} gkii_firestore_codec_test)
endfunction()
