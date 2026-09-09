@echo off
setlocal EnableDelayedExpansion

rem Multi-stage self-host bootstrap, the Windows counterpart to bootstrap.sh.
rem
rem Stage 1 (build\bin\saplangc.exe, C) can only build the Stage-1 language subset. Each later stage
rem adds features used in the compiler's own source, so it must be built by the previous stage's compiler:
rem
rem   Stage 1 (C)              --builds-->  stage2-v0               (source = Stage-1 subset)
rem   stage2-v0 compiler       --builds-->  stage2-generic-structs  (source uses generic functions)
rem   stage2-generic-structs   --builds-->  stage2-v1               (source uses generic structs, List(T), alias)
rem   stage2-v1 compiler       --builds-->  stage2-v2               (source uses comprun + reflection)
rem   stage2-v2 compiler       --builds-->  current source          (uses positional const, List(const u8[]))
rem
rem Each seed tag is frozen Linux-only history, so it has a windows/<tag> counterpart carrying the
rem Windows form of that same source. Each stage's compiler is built once and cached under bootstrap\.
rem
rem Usage:
rem   bootstrap.bat            build the current compiler at build\bin\saplangc2.exe
rem   bootstrap.bat verify     also prove it self-hosts to a byte-identical fixpoint

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
cd /d "%ROOT%"

if not defined SAPLANG_LLVM set "SAPLANG_LLVM=C:\Program Files\LLVM"
set "PATH=%SAPLANG_LLVM%\bin;%PATH%"

set "STAGE1=%ROOT%\build\bin\saplangc.exe"
set "OUT=%ROOT%\build\bin\saplangc2.exe"
set "INCLUDES=stage2/std;stage2"
set "STAGES=stage2-v0 stage2-generic-structs stage2-v1 stage2-v2"

if not exist "%ROOT%\bootstrap" mkdir "%ROOT%\bootstrap"
if not exist "%ROOT%\build\bin" mkdir "%ROOT%\build\bin"

cmake --preset windows || exit /b 1
cmake --build --preset windows || exit /b 1

set "PREV=%STAGE1%"
rem Stage 1's parallel driver has an intermittent segfault race.
set "PREVFLAGS=-j 1"
for %%T in (%STAGES%) do (
    set "SEED=%ROOT%\bootstrap\seed-%%T.exe"
    if not exist "!SEED!" (
        if not exist "%STAGE1%" (
            echo Stage 1 compiler not found at %STAGE1%.
            exit /b 1
        )
        echo Building windows/%%T via !PREV!...
        call :build_stage %%T "!PREV!" "!SEED!" "!PREVFLAGS!"
        if errorlevel 1 exit /b 1
    )
    set "PREV=!SEED!"
    rem stage-2 compilers are single-threaded by default (no race)
    set "PREVFLAGS="
)

echo Building the current compiler with the seed...
"%PREV%" stage2/saplangc.sl -o "%OUT%" -i "%INCLUDES%" -l "LLVM-C" -L "%SAPLANG_LLVM%\lib" -target windows || exit /b 1
echo Compiler: %OUT%

if /i "%~1"=="verify" (
    echo Verifying self-host fixpoint...
    "%OUT%" stage2/saplangc.sl -o "%ROOT%\build\bin\saplangc2.b.exe" -i "%INCLUDES%" -l "LLVM-C" -L "%SAPLANG_LLVM%\lib" -target windows || exit /b 1
    "%ROOT%\build\bin\saplangc2.b.exe" stage2/saplangc.sl -o "%ROOT%\build\bin\saplangc2.c.exe" -i "%INCLUDES%" -l "LLVM-C" -L "%SAPLANG_LLVM%\lib" -target windows || exit /b 1
    fc /b "%ROOT%\build\bin\saplangc2.b.exe" "%ROOT%\build\bin\saplangc2.c.exe" >nul
    if errorlevel 1 (
        echo FAIL: fixpoint not reached ^(b ^!= c^)
        exit /b 1
    )
    echo OK: b == c ^(byte-identical fixpoint^)
)
exit /b 0

rem Build tag %1 with compiler %2 into %3, extra flags %4, from a detached worktree of windows/<tag>.
:build_stage
set "TAG=%~1"
set "CC=%~2"
set "SEEDOUT=%~3"
set "FLAGS=%~4"
set "WT=%TEMP%\saplang-seed-%TAG%"
if exist "%WT%" git worktree remove --force "%WT%" >nul 2>&1
git worktree add --quiet --detach "%WT%" "windows/%TAG%" || (
    echo Tag windows/%TAG% not found; fetch the seed tags before bootstrapping.
    exit /b 1
)
pushd "%WT%"
"%CC%" stage2/saplangc.sl -o "%SEEDOUT%" -i "%INCLUDES%" -l "LLVM-C" -L "%SAPLANG_LLVM%\lib" -target windows %FLAGS%
set "RC=!errorlevel!"
popd
git worktree remove --force "%WT%" >nul 2>&1
exit /b %RC%
