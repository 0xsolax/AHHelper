@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0tools\install-sparkleboost.ps1"
if errorlevel 1 (
  echo.
  echo Installation failed. Please keep the error message above.
  pause
  exit /b 1
)
echo.
pause
