@echo off
set SCRIPT=%~dp0TunnelCleanup.ps1
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
