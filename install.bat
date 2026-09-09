@echo off
setlocal EnableDelayedExpansion

rem Lays out a self-contained install: the binary with std\ beside it, the way saplangc discovers it.
rem
rem   install.bat [DEST]     default DEST=dist\saplang
rem
rem Put DEST on your PATH. saplangc locates std\ from its own module path, so it keeps working
rem wherever DEST is moved to, as long as std\ moves with it.

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

if "%~1"=="" (set "DEST=%ROOT%\dist\saplang") else (set "DEST=%~f1")
set "COMPILER=%ROOT%\build\bin\saplangc2.exe"

if not exist "%COMPILER%" (
    echo error: %COMPILER% not found; run bootstrap.bat first >&2
    exit /b 1
)

if not exist "%DEST%\std" mkdir "%DEST%\std" || exit /b 1
copy /y "%COMPILER%" "%DEST%\saplangc.exe" >nul || exit /b 1
copy /y "%ROOT%\stage2\std\*.sl" "%DEST%\std\" >nul || exit /b 1

set /a COUNT=0
for %%F in ("%DEST%\std\*.sl") do set /a COUNT+=1

echo installed to %DEST%
echo   %DEST%\saplangc.exe
echo   %DEST%\std\  (!COUNT! modules^)
echo.
echo add it to PATH:  set "PATH=%DEST%;%%PATH%%"
exit /b 0
