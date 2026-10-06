@echo off
rem dockur/windows copies this folder to C:\OEM and runs install.bat once, at the
rem end of the unattended installation, as the auto-logon administrator.
rem Everything happens in install.ps1. Its log is C:\OEM\install.log, copied to
rem the shared folder (./shared on the host) when it finishes. The redirect
rem below only catches PowerShell failing to start at all.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" >> "%~dp0install.bat.log" 2>&1
exit /b %ERRORLEVEL%
