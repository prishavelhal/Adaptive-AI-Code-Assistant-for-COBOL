@echo off
rem CobolTutor installer for Windows. Double-click this file, or run it from a
rem terminal with the same options as install.ps1 (try: install.cmd --help).
rem
rem It starts install.ps1 with the execution policy relaxed for this one run
rem only, so nobody has to change their PowerShell settings.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "CT_EXIT=%ERRORLEVEL%"
rem Opened by double-click? Keep the window open so the result can be read.
echo %CMDCMDLINE% | find /i "%~nx0" >nul && pause
exit /b %CT_EXIT%
