@echo off
setlocal
chcp 65001 >nul
set "PS1=%~dp0wechat-gif-compress.ps1"
if not exist "%PS1%" (
    echo [ERROR] wechat-gif-compress.ps1 not found next to this .cmd file.
    echo Please keep both files in the same folder.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo Done. Press any key to close this window...
) else (
    echo Finished with exit code %RC%. Press any key to close this window...
)
pause >nul
endlocal
