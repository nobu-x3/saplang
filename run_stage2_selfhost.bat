@echo off
setlocal EnableDelayedExpansion

rem Build the self-hosted compiler, then compile + run every stage2 test through it.
rem The Windows counterpart to run_stage2_selfhost.sh. A fully green run reports
rem `build: N ok, 0 failed` / `run: N ok, 0 failed` / `mt: 0 failed`.

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
cd /d "%ROOT%"

if not defined SAPLANG_LLVM set "SAPLANG_LLVM=C:\Program Files\LLVM"
set "PATH=%SAPLANG_LLVM%\bin;%PATH%"

call "%ROOT%\bootstrap.bat" || exit /b 1

set "SC=%ROOT%\build\bin\saplangc2.exe"
set "INC=%ROOT%/stage2/std;%ROOT%/stage2;%ROOT%/stage2/tests"
set "TMP_DIR=%TEMP%\saplang-selfhost"
if exist "%TMP_DIR%" rmdir /s /q "%TMP_DIR%"
mkdir "%TMP_DIR%"

if not defined MT_REPEATS set "MT_REPEATS=2"

set /a bok=0, bfail=0, rok=0, rfail=0, mtfail=0

rem The tests write their fixtures into the working directory, so run them out of the temp dir.
pushd "%TMP_DIR%"
for %%F in ("%ROOT%\stage2\tests\*.sl") do (
    if /i not "%%~nF"=="test_util" (
        "%SC%" "%%~fF" -o "%TMP_DIR%\%%~nF.exe" -i "%INC%" -l "LLVM-C" -L "%SAPLANG_LLVM%\lib" -target windows > "%TMP_DIR%\%%~nF.log" 2>&1
        if errorlevel 1 (
            set /a bfail+=1
            echo   BUILD-FAIL: %%~nF
        ) else (
            set /a bok+=1
            "%TMP_DIR%\%%~nF.exe" > "%TMP_DIR%\%%~nF.run.log" 2>&1
            if errorlevel 1 ( set /a rfail+=1 & echo   RUN-FAIL: %%~nF ) else ( set /a rok+=1 )
        )
    )
)
echo build: !bok! ok, !bfail! failed
echo run: !rok! ok, !rfail! failed

rem Second pass through -mt: the parallel path is otherwise untested, and its bugs are races that a
rem single run can miss, so each build is repeated.
for %%F in ("%ROOT%\stage2\tests\*.sl") do (
    if /i not "%%~nF"=="test_util" (
        for /l %%A in (1,1,%MT_REPEATS%) do (
            "%SC%" "%%~fF" -o "%TMP_DIR%\mt-%%~nF.exe" -i "%INC%" -l "LLVM-C" -L "%SAPLANG_LLVM%\lib" -target windows -mt > "%TMP_DIR%\mt-%%~nF.log" 2>&1
            if errorlevel 1 (
                set /a mtfail+=1
                echo   MT-BUILD-FAIL: %%~nF ^(attempt %%A^)
            ) else (
                "%TMP_DIR%\mt-%%~nF.exe" > nul 2>&1
                if errorlevel 1 ( set /a mtfail+=1 & echo   MT-RUN-FAIL: %%~nF ^(attempt %%A^) )
            )
        )
    )
)
echo mt: !mtfail! failed ^(x%MT_REPEATS% each^)
popd

if not !bfail!==0 exit /b 1
if not !rfail!==0 exit /b 1
if not !mtfail!==0 exit /b 1
exit /b 0
