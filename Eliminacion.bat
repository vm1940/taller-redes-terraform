@echo off
color 0C
for /f %%i in ('az account show --query id -o tsv') do set ARM_SUBSCRIPTION_ID=%%i
echo ==================================================
echo   ELIMINACION EXACTA DE INFRAESTRUCTURA
echo   EJECUTADO POR: %USERNAME%
echo   FECHA Y HORA: %DATE% %TIME%
echo ==================================================
echo.
echo Verificando las unicas 2 maquinas activas a destruir...
terraform state list | findstr "azurerm_linux_virtual_machine"
echo.
echo Destruyendo unicamente la infraestructura mapeada...
terraform destroy -auto-approve

set N=0
for /f %%i in ('az vm list -g rg-laboratorio-final --query "[].name" -o tsv 2^>nul') do set /a N+=1
echo.
echo ==================================================
echo   Maquinas restantes despues de borrar: %N%
echo   HORA: %TIME%
echo ==================================================
echo Laboratorio eliminado por completo.
pause