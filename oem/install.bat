@echo off
rem dockur/windows copies this folder to C:\OEM and runs install.bat once, at the
rem end of the unattended installation, as the auto-logon administrator, in a
rem visible "Install" window. Everything happens in install.ps1; its output is
rem shown here and recorded in C:\OEM\install.log, which is mirrored to the
rem shared folder (./shared on the host).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
exit /b %ERRORLEVEL%
