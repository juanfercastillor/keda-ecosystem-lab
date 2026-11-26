@echo off
REM ============================================================
REM Verifica que el entorno este listo para el laboratorio KEDA
REM — variante para cmd.exe (Windows).
REM
REM No modifica nada. Actua como launcher de
REM verificar-prerrequisitos.ps1 (PowerShell esta incluido en
REM Windows; -ExecutionPolicy Bypass evita bloqueos de politica).
REM
REM Uso:
REM   scripts\verificar-prerrequisitos.cmd
REM ============================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verificar-prerrequisitos.ps1"
exit /b %ERRORLEVEL%
