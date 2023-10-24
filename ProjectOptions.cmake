include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(pheps_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(pheps_setup_options)
  option(pheps_ENABLE_HARDENING "Enable hardening" ON)
  option(pheps_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    pheps_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    pheps_ENABLE_HARDENING
    OFF)

  pheps_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR pheps_PACKAGING_MAINTAINER_MODE)
    option(pheps_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(pheps_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(pheps_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(pheps_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(pheps_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(pheps_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(pheps_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(pheps_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(pheps_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(pheps_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(pheps_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(pheps_ENABLE_PCH "Enable precompiled headers" OFF)
    option(pheps_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(pheps_ENABLE_IPO "Enable IPO/LTO" ON)
    option(pheps_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(pheps_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(pheps_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(pheps_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(pheps_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(pheps_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(pheps_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(pheps_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(pheps_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(pheps_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(pheps_ENABLE_PCH "Enable precompiled headers" OFF)
    option(pheps_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      pheps_ENABLE_IPO
      pheps_WARNINGS_AS_ERRORS
      pheps_ENABLE_USER_LINKER
      pheps_ENABLE_SANITIZER_ADDRESS
      pheps_ENABLE_SANITIZER_LEAK
      pheps_ENABLE_SANITIZER_UNDEFINED
      pheps_ENABLE_SANITIZER_THREAD
      pheps_ENABLE_SANITIZER_MEMORY
      pheps_ENABLE_UNITY_BUILD
      pheps_ENABLE_CLANG_TIDY
      pheps_ENABLE_CPPCHECK
      pheps_ENABLE_COVERAGE
      pheps_ENABLE_PCH
      pheps_ENABLE_CACHE)
  endif()

  pheps_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (pheps_ENABLE_SANITIZER_ADDRESS OR pheps_ENABLE_SANITIZER_THREAD OR pheps_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(pheps_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(pheps_global_options)
  if(pheps_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    pheps_enable_ipo()
  endif()

  pheps_supports_sanitizers()

  if(pheps_ENABLE_HARDENING AND pheps_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR pheps_ENABLE_SANITIZER_UNDEFINED
       OR pheps_ENABLE_SANITIZER_ADDRESS
       OR pheps_ENABLE_SANITIZER_THREAD
       OR pheps_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${pheps_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${pheps_ENABLE_SANITIZER_UNDEFINED}")
    pheps_enable_hardening(pheps_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(pheps_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(pheps_warnings INTERFACE)
  add_library(pheps_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  pheps_set_project_warnings(
    pheps_warnings
    ${pheps_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(pheps_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(pheps_options)
  endif()

  include(cmake/Sanitizers.cmake)
  pheps_enable_sanitizers(
    pheps_options
    ${pheps_ENABLE_SANITIZER_ADDRESS}
    ${pheps_ENABLE_SANITIZER_LEAK}
    ${pheps_ENABLE_SANITIZER_UNDEFINED}
    ${pheps_ENABLE_SANITIZER_THREAD}
    ${pheps_ENABLE_SANITIZER_MEMORY})

  set_target_properties(pheps_options PROPERTIES UNITY_BUILD ${pheps_ENABLE_UNITY_BUILD})

  if(pheps_ENABLE_PCH)
    target_precompile_headers(
      pheps_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(pheps_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    pheps_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(pheps_ENABLE_CLANG_TIDY)
    pheps_enable_clang_tidy(pheps_options ${pheps_WARNINGS_AS_ERRORS})
  endif()

  if(pheps_ENABLE_CPPCHECK)
    pheps_enable_cppcheck(${pheps_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(pheps_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    pheps_enable_coverage(pheps_options)
  endif()

  if(pheps_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(pheps_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(pheps_ENABLE_HARDENING AND NOT pheps_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR pheps_ENABLE_SANITIZER_UNDEFINED
       OR pheps_ENABLE_SANITIZER_ADDRESS
       OR pheps_ENABLE_SANITIZER_THREAD
       OR pheps_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    pheps_enable_hardening(pheps_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
