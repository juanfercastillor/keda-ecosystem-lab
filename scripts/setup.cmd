@echo off
REM ============================================================
REM Instala y prepara TODO el entorno del laboratorio KEDA
REM — variante para cmd.exe (Windows).
REM
REM Actua como launcher de setup.ps1 (PowerShell esta incluido en
REM Windows; -ExecutionPolicy Bypass evita bloqueos de politica).
REM
REM Uso:
REM   scripts\setup.cmd
REM   scripts\setup.cmd -Yes
REM   scripts\setup.cmd -SoloVerificar
REM   scripts\setup.cmd -SinScaledObject
REM   scripts\setup.cmd -Kind
REM ============================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
exit /b %ERRORLEVEL%
