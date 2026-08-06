# ---------------------------------------------------------------
#  Instalador RustDesk + config del servidor del Ayto (Ayamonte)
#  Colocar en la misma carpeta que el instalador .exe de RustDesk
#  y el fichero "asistencia_remota.ico".
# ---------------------------------------------------------------

# ============== EDITA ESTOS VALORES CON LOS DATOS REALES ==============
$IdServer      = "192.168.x.x"   # "Servidor de IDs"
$RelayServer   = ""                 # "Servidor Relay" (vacio si no usais uno aparte)
$ApiServer     = ""                 # "Servidor API" (vacio si no usais servidor Pro)
$Key           = "Vuestra_API_KEY"
$NombreAcceso  = "Asistencia remota"          # Nombre del acceso directo del escritorio
$NombreIcono   = "asistencia_remota.ico"      # Debe estar en esta misma carpeta
# ========================================================================

$CarpetaActual    = Split-Path -Parent $MyInvocation.MyCommand.Path
$NombreEsteScript = Split-Path -Leaf $MyInvocation.MyCommand.Path

# Paso 0: limpiar restos de instalaciones anteriores (evita que el
# instalador se quede colgado si ya habia un servicio/proceso a medias
# de una prueba previa).
Get-Process -Name "RustDesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Stop-Service -Name "RustDesk" -Force -ErrorAction SilentlyContinue
if (Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue) {
    sc.exe delete "RustDesk" | Out-Null
    Start-Sleep -Seconds 2
}

# Paso 1: localizar el instalador de RustDesk en esta misma carpeta
$Instalador = Get-ChildItem -Path $CarpetaActual -Filter "*.exe" -File |
              Where-Object { $_.Name -ne $NombreEsteScript } |
              Select-Object -First 1

if (-not $Instalador) {
    Write-Host "No se encontro el instalador de RustDesk (.exe) en esta carpeta."
    exit 1
}

# Paso 2: instalacion silenciosa, con limite de 60s por si se cuelga
$procesoInstalador = Start-Process -FilePath $Instalador.FullName -ArgumentList "--silent-install" -PassThru
if (-not $procesoInstalador.WaitForExit(60000)) {
    $procesoInstalador | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Paso 3: esperar a que el servicio arranque, forzandolo si hace falta
for ($i = 0; $i -lt 20; $i++) {
    $servicio = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
    if ($servicio -and $servicio.Status -eq "Running") { break }
    if ($servicio -and $servicio.Status -eq "Stopped") {
        Start-Service -Name "RustDesk" -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

# Paso 4: parar el servicio y cualquier instancia en ejecucion antes de
# tocar la configuracion (si no, puede quedarse a medias o no aplicarse).
Stop-Service -Name "RustDesk" -Force -ErrorAction SilentlyContinue
Get-Process -Name "RustDesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Paso 5: construir el contenido del RustDesk2.toml
$lineasOpciones = @("custom-rendezvous-server = '$IdServer'", "key = '$Key'")
if ($RelayServer) { $lineasOpciones += "relay-server = '$RelayServer'" }
if ($ApiServer)   { $lineasOpciones += "api-server = '$ApiServer'" }

$contenidoToml = @"
rendezvous_server = '$IdServer'
nat_type = 1
serial = 0

[options]
$($lineasOpciones -join "`n")
"@

# Paso 6: escribir el fichero en las DOS ubicaciones que usa RustDesk en
# Windows: la del servicio (LocalService, necesaria para acceso
# desatendido) y la del usuario actual (para cuando alguien abra la
# ventana de RustDesk normal).
$RutaServicio = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml"
$RutaUsuario  = Join-Path $env:APPDATA "RustDesk\config\RustDesk2.toml"

foreach ($ruta in @($RutaServicio, $RutaUsuario)) {
    $carpetaDestino = Split-Path -Parent $ruta
    if (-not (Test-Path $carpetaDestino)) {
        New-Item -ItemType Directory -Path $carpetaDestino -Force | Out-Null
    }
    Set-Content -Path $ruta -Value $contenidoToml -Encoding UTF8 -Force
}

# Paso 7: volver a arrancar el servicio con la configuracion ya aplicada
Start-Service -Name "RustDesk" -ErrorAction SilentlyContinue

# Paso 8: borrar el/los accesos directos que haya creado el propio
# instalador de RustDesk (escritorio y menu inicio), para que solo quede
# el nuestro personalizado.
$RutasABuscar = @(
    "$env:Public\Desktop",
    [Environment]::GetFolderPath("CommonStartMenu") + "\Programs",
    [Environment]::GetFolderPath("StartMenu") + "\Programs"
)
foreach ($carpetaBusqueda in $RutasABuscar) {
    if (Test-Path $carpetaBusqueda) {
        Get-ChildItem -Path $carpetaBusqueda -Filter "*RustDesk*.lnk" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -ne $NombreAcceso } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# Paso 9: crear el acceso directo personalizado en el escritorio
# (nombre + icono propios del Ayto, en vez del generico de RustDesk).
$RutaExeInstalado = "C:\Program Files\RustDesk\RustDesk.exe"
$RutaIconoOrigen  = Join-Path $CarpetaActual $NombreIcono

if ((Test-Path $RutaExeInstalado) -and (Test-Path $RutaIconoOrigen)) {
    # Se copia el icono a una ubicacion permanente del PC (no del pen),
    # para que el acceso directo siga funcionando aunque se quite el pen.
    $CarpetaIconoDestino = "C:\ProgramData\AytoAyamonte"
    if (-not (Test-Path $CarpetaIconoDestino)) {
        New-Item -ItemType Directory -Path $CarpetaIconoDestino -Force | Out-Null
    }
    $RutaIconoDestino = Join-Path $CarpetaIconoDestino $NombreIcono
    Copy-Item -Path $RutaIconoOrigen -Destination $RutaIconoDestino -Force

    $RutaAccesoDirecto = Join-Path "$env:Public\Desktop" "$NombreAcceso.lnk"
    $WshShell = New-Object -ComObject WScript.Shell
    $Acceso = $WshShell.CreateShortcut($RutaAccesoDirecto)
    $Acceso.TargetPath = $RutaExeInstalado
    $Acceso.IconLocation = $RutaIconoDestino
    $Acceso.Description = "Asistencia remota - Ayuntamiento de Ayamonte"
    $Acceso.Save()

    Write-Host "Acceso directo '$NombreAcceso' creado en el escritorio."
} else {
    Write-Host "AVISO: no se pudo crear el acceso directo (falta el .exe instalado o el .ico en la carpeta)."
}

Write-Host "RustDesk instalado y configurado."
