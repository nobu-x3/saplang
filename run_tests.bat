@echo off
setlocal

rem Thin wrapper over the CMake "windows" preset (the same one Visual Studio
rem uses). CMake stages the module_tests fixtures and runs the suite via CTest,
rem so there is nothing to copy or path-fix here.

rem Prepend the toolchain bin dir for robustness if LLVM isn't already on PATH.
set "PATH=C:\Program Files\LLVM\bin;%PATH%"

cmake --preset windows || exit /b 1
cmake --build --preset windows || exit /b 1
ctest --preset windows
