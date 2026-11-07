@echo off
setlocal
cd /d "%~dp0..\.."

set "NODE=%ProgramFiles%\nodejs\node.exe"
if not exist "%NODE%" set "NODE=node"

echo.>>"%~dp0refresh.log"
echo [%DATE% %TIME%] Refreshing Oribos Exchange Forever data>>"%~dp0refresh.log"
"%NODE%" "%~dp0build.js" %* >>"%~dp0refresh.log" 2>&1
exit /b %ERRORLEVEL%
