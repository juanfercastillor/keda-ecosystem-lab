@echo off
REM ============================================================
REM Generador de carga HTTP para el laboratorio de elasticidad
REM con KEDA — variante para cmd.exe (Windows).
REM
REM Lanza rondas de peticiones concurrentes contra /api/work.
REM Cada peticion consume CPU durante `ms` milisegundos, elevando
REM la utilizacion de CPU del pod y disparando el escalado.
REM
REM cmd.exe no puede gestionar concurrencia ni esperar procesos
REM en segundo plano, por lo que este script actua como launcher
REM de carga.ps1 (PowerShell esta incluido en Windows; la opcion
REM -ExecutionPolicy Bypass evita bloqueos de politica de scripts).
REM
REM Uso:
REM   carga.cmd
REM   carga.cmd 40 600
REM   carga.cmd 10 300 "http://localhost:8080/api/work?ms=500"
REM
REM Argumentos: [concurrencia] [duracion_segundos] [url]
REM ============================================================

setlocal

set "CONC=%~1"
set "DUR=%~2"
set "URL=%~3"

if "%CONC%"=="" set "CONC=20"
if "%DUR%"=="" set "DUR=300"
if "%URL%"=="" set "URL=http://localhost:8080/api/work?ms=300"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0carga.ps1" -Concurrencia %CONC% -DuracionSegundos %DUR% -Url "%URL%"

endlocal
