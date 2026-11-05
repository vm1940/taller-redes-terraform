@echo off
color 0D
echo ==================================================
echo   Iniciando Automatizacion Terraform...
echo   EJECUTADO POR: %USERNAME%
echo   FECHA Y HORA: %DATE% %TIME%
echo ==================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Creacion.ps1"
echo.
echo Despliegue finalizado. Espera 1 minuto antes de los pings.
pause