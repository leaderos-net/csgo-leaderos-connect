@echo off
setlocal

set SP=scripting\spcomp.exe
set SOURCE=leaderos_connect.sp
set OUT=upload\leaderos_connect.smx

echo Compiling %SOURCE%...

if not exist "%SP%" (
    echo ERROR: %SP% not found.
    echo Download SourceMod and place spcomp.exe in the scripting\ folder.
    pause
    exit /b 1
)

if not exist "upload" mkdir upload

"%SP%" "%SOURCE%" -o"%OUT%"

if %ERRORLEVEL% neq 0 (
    echo.
    echo Compilation FAILED.
    pause
    exit /b 1
)

echo.
echo Done: %OUT%
pause
