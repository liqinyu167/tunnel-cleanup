@echo off
set SCRIPT=%~dp0TunnelCleanup.ps1
net session >nul 2>&1
if %errorlevel% neq 0 (
  C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','%SCRIPT%') -Verb RunAs"
  exit /b
)
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
