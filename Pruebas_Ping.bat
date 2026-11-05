@echo off
color 0B
for /f %%i in ('terraform output -raw ip_maquina_1') do set IP1=%%i

echo ==================================================
echo   PRUEBAS DE RED ESTRICTAS SEGUN RUBRICA
echo   EJECUTADO POR: %USERNAME% 
echo   FECHA Y HORA: %DATE% %TIME%
echo ==================================================
echo.
echo [Prueba 1] Ping desde el PC alojante hacia la VM (DEBE FALLAR / DROP)
ping -n 4 %IP1%

echo.
echo ==================================================
echo [Prueba 2] Ping interno entre Maquina 1 y Maquina 2 (DEBE FUNCIONAR)
call az vm run-command invoke -g rg-laboratorio-final -n maquina-1 --command-id RunShellScript --scripts "ping -c 4 10.0.0.5" --query "value[0].message" -o tsv
echo.
pause