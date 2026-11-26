@echo off
REM ============================================================
REM Limpia el entorno creado por setup — variante para cmd.exe.
REM
REM Actua como launcher de cleanup.ps1 (-ExecutionPolicy Bypass
REM evita bloqueos de politica de scripts).
REM
REM Uso:
REM   scripts\cleanup.cmd
REM   scripts\cleanup.cmd -Yes
REM   scripts\cleanup.cmd -Yes -Todo
REM ============================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup.ps1" %*
exit /b %ERRORLEVEL%
