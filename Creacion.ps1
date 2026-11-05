$env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
$rg = "rg-laboratorio-final"
$cantidadVMs = 2
$precioMax = 100   # USD/mes por VM (pon 999999 si no quieres limite)

Write-Host "=================================================="
Write-Host " VALIDACION DE SEGURIDAD Y DESPLIEGUE (MAXIMO $cantidadVMs MAQUINAS)"
Write-Host " USUARIO WINDOWS: $env:USERNAME"
Write-Host " FECHA Y HORA: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
Write-Host "=================================================="

# PREVENCION DE MULTIPLES DESPLIEGUES (estado de Terraform y Azure real)
$vm_count = @(terraform state list 2>$null | Select-String "azurerm_linux_virtual_machine").Count
if ($vm_count -ge $cantidadVMs) {
    Write-Host ""
    Write-Host "[ALERTA] Terraform detecto que ya existen $vm_count maquinas operando."
    Write-Host "Ejecuta Eliminacion.bat para limpiar antes de crear nuevas."
    exit 1
}

$vms_azure = @(az vm list -g $rg -o json 2>$null | ConvertFrom-Json)
if ($LASTEXITCODE -eq 0 -and $vms_azure.Count -ge $cantidadVMs) {
    Write-Host "[ALERTA] Azure reporta $($vms_azure.Count) maquinas en $rg. Proceso bloqueado."
    exit 1
}
Write-Host "[OK] Limite verificado. Se desplegaran exactamente $cantidadVMs maquinas."

# REGIONES PERMITIDAS POR LA POLITICA DE TU SUSCRIPCION (Azure for Students)
$regiones = @("mexicocentral", "chilecentral", "centralus", "canadacentral", "westus3")

# Tamanos candidatos (se ordenan por precio automaticamente)
$tamanos = @(
    "Standard_B1ls", "Standard_B1s", "Standard_B1ms",
    "Standard_B2ats_v2", "Standard_B2ts_v2", "Standard_B2ls_v2",
    "Standard_B2s", "Standard_B2s_v2", "Standard_B2as_v2", "Standard_B2ms",
    "Standard_B4ms", "Standard_B4s_v2",
    "Standard_D2s_v3", "Standard_D2as_v5", "Standard_D2s_v5", "Standard_D2ds_v5", "Standard_DS1_v2", "Standard_DS2_v2"
)

# Precio mensual estimado (USD), solo si la API de precios no responde
$respaldo = @{
    "Standard_B1ls" = 4;  "Standard_B1s" = 8;   "Standard_B1ms" = 15
    "Standard_B2ats_v2" = 10; "Standard_B2ts_v2" = 14; "Standard_B2ls_v2" = 30
    "Standard_B2s" = 30;  "Standard_B2s_v2" = 35; "Standard_B2as_v2" = 33; "Standard_B2ms" = 61
    "Standard_B4ms" = 121; "Standard_B4s_v2" = 70
    "Standard_D2s_v3" = 70; "Standard_D2as_v5" = 63; "Standard_D2s_v5" = 70; "Standard_D2ds_v5" = 83
    "Standard_DS1_v2" = 53; "Standard_DS2_v2" = 106
}

function Get-PrecioMensual($reg, $tam) {
    try {
        $filtro = "serviceName eq 'Virtual Machines' and armRegionName eq '$reg' and armSkuName eq '$tam' and priceType eq 'Consumption'"
        $url = "https://prices.azure.com/api/retail/prices?`$filter=" + [uri]::EscapeDataString($filtro)
        $items = (Invoke-RestMethod -Uri $url -TimeoutSec 15).Items |
            Where-Object { $_.productName -notmatch "Windows" -and $_.skuName -notmatch "Spot|Low Priority" }
        $item = $items | Sort-Object retailPrice | Select-Object -First 1
        if ($item) { return [math]::Round($item.retailPrice * 730, 2) }
    }
    catch { }
    return $null
}

terraform init

$exito = $false
$intentos = 0
$region_elegida = ""
$tamano_elegido = ""

Write-Host ""
Write-Host "##################################################"
Write-Host " BUSQUEDA UNICA EN $($regiones.Count) REGIONES PERMITIDAS (max $precioMax USD/mes por VM)"
Write-Host "##################################################"

foreach ($reg in $regiones) {
    if ($exito) { break }
    Write-Host ""
    Write-Host "Consultando region: ${reg} ..."

    # Sin filtro --size para poder evaluar B-series y D-series
    $skus = az vm list-skus --location $reg --resource-type virtualMachines -o json 2>$null | ConvertFrom-Json
    if (-not $skus) {
        Write-Host "  Sin datos de SKUs en ${reg}, se omite."
        continue
    }

    $uso = az vm list-usage --location $reg -o json 2>$null | ConvertFrom-Json
    $totalCores = $null
    if ($uso) {
        $totalCores = $uso | Where-Object { $_.name.value -eq "cores" } | Select-Object -First 1
        if ($totalCores) {
            Write-Host "  Cuota total de vCPUs: $($totalCores.currentValue) usados de $($totalCores.limit)"
        }
    }
    else {
        Write-Host "  (No se pudo leer la cuota en ${reg}; se intentara igual)"
    }

    $disponibles = @()
    foreach ($tam in $tamanos) {
        $sku = $skus | Where-Object { $_.name -eq $tam } | Select-Object -First 1
        if (-not $sku) { continue }   # no existe en la region (no se imprime para no llenar la pantalla)

        $bloqueado = @($sku.restrictions | Where-Object { $_.type -eq "Location" })
        if ($bloqueado.Count -gt 0) {
            Write-Host "  ${tam}: bloqueado para tu suscripcion en esta region"
            continue
        }

        if ($uso) {
            $vcpus = [int](($sku.capabilities | Where-Object { $_.name -eq "vCPUs" }).value)
            $necesarios = $vcpus * $cantidadVMs
            $familia = $uso | Where-Object { $_.name.value -eq $sku.family } | Select-Object -First 1
            $okFamilia = $familia -and (([int]$familia.limit - [int]$familia.currentValue) -ge $necesarios)
            $okTotal = $totalCores -and (([int]$totalCores.limit - [int]$totalCores.currentValue) -ge $necesarios)
            if (-not $okFamilia) {
                $lim = if ($familia) { $familia.limit } else { "sin familia" }
                Write-Host "  ${tam}: cuota de familia insuficiente (limite: $lim, necesarios: $necesarios)"
                continue
            }
            if (-not $okTotal) {
                Write-Host "  ${tam}: cuota total de vCPUs insuficiente (necesarios: $necesarios)"
                continue
            }
        }

        $precio = Get-PrecioMensual $reg $tam
        $fuente = "API de precios"
        if ($null -eq $precio) {
            $precio = $respaldo[$tam]
            $fuente = "estimado"
        }
        if ($null -eq $precio) { $precio = 50; $fuente = "estimado generico" }
        if ($precio -gt $precioMax) {
            Write-Host "  ${tam}: aprox. $precio USD/mes supera el maximo de $precioMax"
            continue
        }

        $disponibles += [pscustomobject]@{ Tamano = $tam; Precio = $precio; Fuente = $fuente }
    }

    if ($disponibles.Count -eq 0) {
        Write-Host "  Region ${reg} sin tamanos validos."
        continue
    }

    # Mas barato primero
    $disponibles = @($disponibles | Sort-Object Precio)
    Write-Host "  Region valida: ${reg}. Tamanos (de menor a mayor precio): $(($disponibles | ForEach-Object { "$($_.Tamano) ($($_.Precio))" }) -join ', ')"

    foreach ($d in $disponibles) {
        if ($exito) { break }
        $intentos++
        Write-Host "=================================================="
        Write-Host " INTENTO $intentos : $($d.Tamano) en ${reg}"
        Write-Host " Precio aprox. por VM: $($d.Precio) USD/mes ($($d.Fuente))"
        Write-Host " HORA: $(Get-Date -Format 'HH:mm:ss')"
        Write-Host "=================================================="

        terraform apply -var="location=$reg" -var="vm_size=$($d.Tamano)" -auto-approve
        if ($LASTEXITCODE -eq 0) {
            $exito = $true
            $region_elegida = $reg
            $tamano_elegido = $d.Tamano
        }
        else {
            Write-Host "[X] Fallo en ${reg} / $($d.Tamano). Limpiando y probando la siguiente combinacion..."
            terraform destroy -var="location=$reg" -var="vm_size=$($d.Tamano)" -auto-approve
        }
    }
}

if (-not $exito) {
    Write-Host ""
    Write-Host "[ERROR CRITICO] No se lograron crear las $cantidadVMs VM en ninguna region ($intentos intentos)."
    Write-Host "Revisa arriba el motivo de descarte de cada tamano (cuota, bloqueo o precio)."
    exit 1
}

Write-Host ""
Write-Host "[OK] Despliegue exitoso. Region: $region_elegida | Tamano: $tamano_elegido"
Write-Host ""
Write-Host "=================================================="
Write-Host " INVENTARIO FINAL (VERIFICANDO QUE SEAN SOLO $cantidadVMs)"
Write-Host "=================================================="
az vm list -g $rg -d --query "[].{Nombre:name, Estado:powerState, IP_Privada:privateIps, IP_Publica:publicIps}" -o table

$final = az vm list -g $rg --query "length(@)" -o tsv 2>$null
if ("$final".Trim() -match '^\d+$' -and [int]("$final".Trim()) -eq $cantidadVMs) {
    Write-Host "[OK] Exactamente $final maquinas operando."
}
else {
    Write-Host "[ALERTA] Se esperaban $cantidadVMs maquinas y hay '$final'."
}$vms = az vm list -g $rg -o json 2>$null | ConvertFrom-Json
$final = @($vms).Count
if ($final -eq $cantidadVMs) {
    Write-Host "[OK] Exactamente $final maquinas operando."
}
else {
    Write-Host "[ALERTA] Se esperaban $cantidadVMs maquinas y hay $final."
}