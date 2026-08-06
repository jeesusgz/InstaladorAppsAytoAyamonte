<#
    LAUNCHER AYTO AYAMONTE - Version SOLO OFFLINE
    ---------------------------------
    Version sin modo ONLINE/winget: instala unicamente desde los
    instaladores locales de la carpeta "apps". Pensada para equipos donde
    FortiEDR (u otro EDR) bloquea las conexiones de winget al no tener
    excepcion configurada para ese proceso.

    Uso:
      1. Coloca este script, catalog.json y la carpeta "apps" TODO JUNTO
         (en el pen, o en la carpeta compartida de red).
      2. Ejecuta con:
             powershell -ExecutionPolicy Bypass -File Launcher_Offline.ps1
      3. Para convertirlo en .exe: ver instrucciones al final del fichero.

    Este prototipo NO instala nada realmente salvo que actives
    $MODO_REAL = $true más abajo. Por defecto simula la instalación.
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Windows.Forms   # necesario para no congelar la ventana durante la instalación
Add-Type -AssemblyName System.Drawing         # necesario para extraer iconos reales de los .exe
Add-Type -AssemblyName Microsoft.VisualBasic  # necesario para el cuadro de "nombre del PC"

# ------------------- CONFIGURACIÓN -------------------
$MODO_REAL   = $true   # Cambiar a $true cuando esté probado en un equipo real
# $PSScriptRoot viene vacío cuando el script se ejecuta compilado como .exe
# (ps2exe), así que hay que detectar la carpeta real del proceso en ese caso.
if ($PSScriptRoot) {
    $RutaBase = $PSScriptRoot
} else {
    $RutaBase = Split-Path -Parent -Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$RutaCatalog = Join-Path $RutaBase "catalog.json"
$script:ModoActual = "offline"  # Esta versión del launcher es SOLO offline (sin winget)

if (-not (Test-Path $RutaCatalog)) {
    [System.Windows.MessageBox]::Show("No se encuentra catalog.json en:`n$RutaCatalog", "Error", "OK", "Error")
    exit
}

$Catalogo = Get-Content $RutaCatalog -Raw -Encoding UTF8 | ConvertFrom-Json

# ------------------- ESTILOS / XAML -------------------
[xml]$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Aplicaciones (Solo Offline) - Ayuntamiento de Ayamonte (v1.6)"
        Height="600" Width="900"
        WindowStartupLocation="CenterScreen"
        Background="#1c1c1c">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="10">
                            <ContentPresenter HorizontalAlignment="Center"
                                               VerticalAlignment="Center"
                                               Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.7"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="70"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="4"/>
            <RowDefinition Height="30"/>
        </Grid.RowDefinitions>

        <!-- Cabecera -->
        <Border Grid.Row="0" Background="#141414">
            <DockPanel LastChildFill="True" Margin="15,0,15,0">
                <TextBlock Text="Launcher Informática · Ayto. Ayamonte"
                           Foreground="White" FontSize="20" FontWeight="Bold"
                           VerticalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right"
                            DockPanel.Dock="Right" VerticalAlignment="Center">
                    <Button x:Name="BtnUnirDominio" Content="🖥️ Unir al dominio"
                            Width="160" Height="35" Margin="5,0,0,0"
                            Background="#232323" Foreground="White"
                            Visibility="Collapsed"/>
                    <Button x:Name="BtnVolver" Content="&#8592; Departamentos"
                            Width="150" Height="35" Margin="5,0,0,0"
                            Visibility="Collapsed"/>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- Contenido -->
        <Grid x:Name="PanelContenido" Grid.Row="1" Margin="20">

            <!-- Panel de departamentos: rejilla fija de 2 columnas, así el
                 orden del catálogo decide siempre la misma posición -->
            <UniformGrid x:Name="PanelDepartamentos" Columns="2"
                       HorizontalAlignment="Center" VerticalAlignment="Center"
                       Visibility="Visible"/>

            <!-- Panel de programas -->
            <ScrollViewer x:Name="ScrollProgramas" Visibility="Collapsed"
                          VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="PanelProgramas"/>
            </ScrollViewer>
        </Grid>

        <ProgressBar x:Name="BarraProgreso" Grid.Row="2" Height="4" BorderThickness="0"
                     IsIndeterminate="False" Visibility="Collapsed"
                     Foreground="#E24B4A" Background="Transparent"/>

        <!-- Barra de estado -->
        <Border Grid.Row="3" Background="#141414">
            <TextBlock x:Name="TxtEstado" Text="Selecciona un modo para empezar." Margin="10,0,0,0"
                       VerticalAlignment="Center" Foreground="#999"/>
        </Border>
    </Grid>
</Window>
"@

$Reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($Reader)

$PanelDepartamentos = $Window.FindName("PanelDepartamentos")
$PanelProgramas     = $Window.FindName("PanelProgramas")
$ScrollProgramas    = $Window.FindName("ScrollProgramas")
$BtnVolver          = $Window.FindName("BtnVolver")
$BtnUnirDominio     = $Window.FindName("BtnUnirDominio")
$TxtEstado          = $Window.FindName("TxtEstado")
$BarraProgreso      = $Window.FindName("BarraProgreso")
$PanelContenido     = $Window.FindName("PanelContenido")

# ------------------- FUNCIONES -------------------
# Declaradas como "global:" para que los closures de los botones
# (creados con GetNewClosure()) puedan encontrarlas en tiempo de ejecución.

function global:Set-Estado($texto) {
    $TxtEstado.Text = $texto
}

function global:Mostrar-Progreso() {
    $BarraProgreso.IsIndeterminate = $true
    $BarraProgreso.Visibility = "Visible"
}

function global:Ocultar-Progreso() {
    $BarraProgreso.IsIndeterminate = $false
    $BarraProgreso.Visibility = "Collapsed"
}

# Espera a que un proceso termine SIN congelar la ventana: va bombeando los
# eventos de la interfaz cada pocos milisegundos, así la barra de progreso
# sigue animándose y la ventana no aparece como "no responde".
function global:Esperar-ProcesoConUI($proceso) {
    while (-not $proceso.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
}

function global:Instalar-Winget($idWinget, $nombre, $argsExtra) {
    Set-Estado "Instalando $nombre (winget)..."
    if ($MODO_REAL) {
        Mostrar-Progreso
        $argumentos = "install --id $idWinget --accept-package-agreements --accept-source-agreements -e"
        if ($argsExtra) { $argumentos += " $argsExtra" }
        $proceso = Start-Process -FilePath "winget" -ArgumentList $argumentos -PassThru
        Esperar-ProcesoConUI $proceso
        Ocultar-Progreso
        if ($proceso.ExitCode -eq 0) {
            Set-Estado "$nombre instalado correctamente."
        } else {
            Set-Estado "⚠ ${nombre}: fallo en la instalación (código $($proceso.ExitCode)). Revisa que hay internet."
        }
    } else {
        Mostrar-Progreso
        Start-Sleep -Milliseconds 800   # simulación
        Ocultar-Progreso
        Set-Estado "$nombre instalado correctamente."
    }
}

# Busca dentro de una carpeta el único instalador (.exe o .msi) que haya,
# sin importar su nombre exacto (así no hay que tocar el JSON cuando el
# fichero descargado trae la versión en el nombre). Si hay varios, coge
# el más reciente y avisa.
function global:Obtener-InstaladorEnCarpeta($carpetaCompleta) {
    if (-not (Test-Path $carpetaCompleta)) { return $null }

    # Prioridad 1: si hay un .ps1/.bat/.cmd (script "envoltorio" para
    # instalaciones en varios pasos, ej. RustDesk: instalar + escribir
    # config), se usa ese. Se prioriza .ps1 sobre .bat si hubiera ambos.
    # También cuentan como wrapper los .exe cuyo NOMBRE empiece por
    # "Instalar_" — son wrappers compilados con ps2exe (para que Forti no
    # los vea como "PowerShell ejecutando cosas" y se puedan exceptuar
    # como un programa normal). Así no se confunden con el instalador
    # real al que envuelven, que también es un .exe pero con otro nombre.
    $wrapper = Get-ChildItem -Path $carpetaCompleta -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Extension -in ".ps1", ".bat", ".cmd" -or $_.Name -like "Instalar_*.exe" } |
               Sort-Object @{Expression = { $_.Extension -eq ".ps1" -or $_.Name -like "Instalar_*.exe" }; Descending = $true }, LastWriteTime -Descending |
               Select-Object -First 1
    if ($wrapper) { return $wrapper.FullName }

    # Prioridad 2: instalador normal .exe/.msi
    $candidatos = Get-ChildItem -Path $carpetaCompleta -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Extension -in ".exe", ".msi" }

    if ($candidatos.Count -eq 0) { return $null }

    if ($candidatos.Count -gt 1) {
        $masReciente = $candidatos | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        [System.Windows.MessageBox]::Show(
            "Hay $($candidatos.Count) instaladores en:`n$carpetaCompleta`n`nSe usará el más reciente:`n$($masReciente.Name)`n`nBorra los antiguos para evitar confusiones.",
            "Aviso", "OK", "Warning")
        return $masReciente.FullName
    }

    return $candidatos[0].FullName
}

# Busca un .exe "de verdad" en la carpeta, IGNORANDO wrappers .ps1/.bat/.cmd
# y también los .msi (que no tienen icono extraíble). Se usa solo para
# sacar el icono a mostrar en la tarjeta — nunca para decidir qué se
# ejecuta al instalar (eso lo sigue decidiendo Obtener-InstaladorEnCarpeta).
function global:Buscar-ExeParaIcono($carpetaCompleta) {
    if (-not (Test-Path $carpetaCompleta)) { return $null }
    $exe = Get-ChildItem -Path $carpetaCompleta -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Extension -eq ".exe" -and $_.Name -notlike "Instalar_*.exe" } |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($exe) { return $exe.FullName }
    return $null
}

# Ejecuta el instalador detectado y devuelve $true/$false según el código
# de salida real del proceso (0 = éxito). Usa la carpeta que lo contiene
# como directorio de trabajo (importante para instaladores que referencian
# ficheros relativos, ej. TRANSFORMS="config.mst" de microCLAUDIA).
function global:Ejecutar-Instalador($instalador, $flags, $carpetaCompleta) {
    $proceso = $null
    if ($instalador -like "*.msi") {
        $proceso = Start-Process "msiexec.exe" -ArgumentList "/i `"$instalador`" $flags" -WorkingDirectory $carpetaCompleta -PassThru
    } elseif ($instalador -like "*.ps1") {
        $proceso = Start-Process "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$instalador`" $flags" -WorkingDirectory $carpetaCompleta -WindowStyle Hidden -PassThru
    } elseif ($instalador -like "*.bat" -or $instalador -like "*.cmd") {
        $proceso = Start-Process "cmd.exe" -ArgumentList "/c `"$instalador`" $flags" -WorkingDirectory $carpetaCompleta -PassThru
    } else {
        $proceso = Start-Process $instalador -ArgumentList $flags -WorkingDirectory $carpetaCompleta -PassThru
    }
    Esperar-ProcesoConUI $proceso
    # Códigos de salida habituales que también se consideran éxito:
    # 0 = OK, 3010 = OK pero pide reiniciar (típico de MSI)
    return @{ Exito = ($proceso.ExitCode -in 0, 3010); CodigoSalida = $proceso.ExitCode }
}

function global:Instalar-Vivo($rutaRelativaCarpeta, $flags, $nombre) {
    $carpetaCompleta = Join-Path $RutaBase $rutaRelativaCarpeta
    Set-Estado "Instalando $nombre..."
    if ($MODO_REAL) {
        $instalador = Obtener-InstaladorEnCarpeta $carpetaCompleta
        if (-not $instalador) {
            [System.Windows.MessageBox]::Show("No hay ningún instalador (.exe/.msi/.bat) en:`n$carpetaCompleta", "Error", "OK", "Error")
            Set-Estado "⚠ ${nombre}: no se encontró instalador."
            return
        }
        Mostrar-Progreso
        $resultado = Ejecutar-Instalador $instalador $flags $carpetaCompleta
        Ocultar-Progreso
        if ($resultado.Exito) {
            Set-Estado "$nombre instalado correctamente."
        } else {
            Set-Estado "⚠ ${nombre}: fallo en la instalación (código $($resultado.CodigoSalida))."
        }
    } else {
        Mostrar-Progreso
        Start-Sleep -Milliseconds 800
        Ocultar-Progreso
        Set-Estado "$nombre instalado correctamente."
    }
}

function global:Instalar-VersionadoLocal($rutaRelativaCarpeta, $flags, $version, $nombre) {
    $carpetaCompleta = Join-Path (Join-Path $RutaBase $rutaRelativaCarpeta) $version
    Set-Estado "Instalando $nombre v$version..."
    if ($MODO_REAL) {
        $instalador = Obtener-InstaladorEnCarpeta $carpetaCompleta
        if (-not $instalador) {
            [System.Windows.MessageBox]::Show("No hay ningún instalador (.exe/.msi/.bat) en:`n$carpetaCompleta", "Error", "OK", "Error")
            Set-Estado "⚠ $nombre v${version}: no se encontró instalador."
            return
        }
        Mostrar-Progreso
        $resultado = Ejecutar-Instalador $instalador $flags $carpetaCompleta
        Ocultar-Progreso
        if ($resultado.Exito) {
            Set-Estado "$nombre v$version instalado correctamente."
        } else {
            Set-Estado "⚠ $nombre v${version}: fallo en la instalación (código $($resultado.CodigoSalida))."
        }
    } else {
        Mostrar-Progreso
        Start-Sleep -Milliseconds 800
        Ocultar-Progreso
        Set-Estado "$nombre v$version instalado correctamente."
    }
}

function global:Obtener-VersionesDisponibles($rutaRelativaCarpeta) {
    $rutaCompleta = Join-Path $RutaBase $rutaRelativaCarpeta
    if (Test-Path $rutaCompleta) {
        return Get-ChildItem -Path $rutaCompleta -Directory | Select-Object -ExpandProperty Name | Sort-Object -Descending
    }
    return @("(sin versiones encontradas)")
}

# Busca en el registro de Windows (32 y 64 bits, máquina y usuario) un programa
# instalado cuyo nombre visible contenga $nombreBusqueda, y devuelve su versión.
# Devuelve $null si no lo encuentra (no está instalado).
# $arquitectura: opcional, "32" o "64". Si se indica, solo busca en la
# rama del registro correspondiente a esa arquitectura (más fiable que
# distinguir por texto del nombre, que puede ser casi idéntico entre la
# versión de 32 y 64 bits de un mismo programa, como pasa con Java).
function global:Obtener-VersionInstaladaRegistro($nombreBusqueda, $arquitectura = $null) {
    if (-not $nombreBusqueda) { return $null }

    $rutaWow = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    $rutaNativa = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    $rutaUsuario = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"

    $rutas = switch ($arquitectura) {
        "32" { @($rutaWow) }                              # SOLO 32 bits (WOW6432Node)
        "64" { @($rutaNativa, $rutaUsuario) }              # SOLO 64 bits (rama nativa)
        default { @($rutaNativa, $rutaWow, $rutaUsuario) } # sin distinguir, como antes
    }

    foreach ($ruta in $rutas) {
        $items = Get-ItemProperty -Path $ruta -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "*$nombreBusqueda*" }
        if ($items) {
            return ($items | Select-Object -First 1).DisplayVersion
        }
    }
    return $null
}

# Busca la versión instalada de un producto MSI por su ProductCode exacto
# (el mismo GUID que usa Windows como nombre de la clave en el registro).
# Es una comprobación exacta, sin ambigüedad de nombres.
function global:Obtener-VersionPorProductCode($productCode) {
    if (-not $productCode) { return $null }
    $rutas = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$productCode",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$productCode",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$productCode"
    )
    foreach ($ruta in $rutas) {
        if (Test-Path $ruta) {
            return (Get-ItemProperty -Path $ruta -ErrorAction SilentlyContinue).DisplayVersion
        }
    }
    return $null
}

# Lee los metadatos (nombre, versión, y ProductCode si es MSI) directamente
# del propio fichero instalador, SIN ejecutarlo. Esta es la única fuente de
# verdad: no depende de que nadie escriba a mano una versión en el catálogo.
# Extrae el icono real incrustado en un .exe (el mismo que se ve en el
# Explorador de Windows) y lo convierte a un formato que WPF puede pintar.
# Devuelve $null si falla o si el fichero no es un .exe (los .msi no se
# leen por este método; en ese caso se usa el emoji de respaldo).
# Extrae un icono real desde un fichero: .exe/.dll (icono incrustado) o
# .ico (fichero de icono suelto). Lo convierte a un formato que WPF puede
# pintar. Devuelve $null si falla o el fichero no existe.
# Tipo auxiliar para poder llamar a ExtractIconEx de Windows, que extrae
# el icono EXACTO de un índice/ID de recurso concreto dentro de un .exe/.dll
# — a diferencia de ExtractAssociatedIcon, que ignora el índice y a veces
# devuelve un icono genérico si el DisplayIcon apuntaba a uno específico
# (muy típico en instalaciones vía MSI, con índices negativos tipo ",-101").
if (-not ("AytoIconHelper" -as [type])) {
    Add-Type -Name IconHelper -Namespace AytoIconHelper -MemberDefinition @"
        [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
        public static extern int ExtractIconEx(string szFileName, int nIconIndex, System.IntPtr[] phiconLarge, System.IntPtr[] phiconSmall, int nIcons);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool DestroyIcon(System.IntPtr hIcon);
"@
}

function global:Obtener-IconoDesdeExe($rutaFichero, $indice = 0) {
    if (-not $rutaFichero -or -not (Test-Path $rutaFichero)) { return $null }
    if ($rutaFichero -like "*.msi") {
        # Los .msi no llevan un icono de app extraíble de forma directa:
        # Windows devuelve el icono GENÉRICO de "paquete de instalación"
        # (el mismo para cualquier .msi), que parece válido pero es
        # engañoso. Mejor caer al emoji de respaldo que mostrar eso.
        return $null
    }
    try {
        if ($rutaFichero -like "*.ico") {
            $iconoGdi = New-Object System.Drawing.Icon($rutaFichero)
        } else {
            # Extracción por índice exacto (respeta índices negativos de recurso)
            $handlesGrandes = New-Object System.IntPtr[] 1
            $handlesPequenos = New-Object System.IntPtr[] 1
            $encontrados = [AytoIconHelper.IconHelper]::ExtractIconEx($rutaFichero, $indice, $handlesGrandes, $handlesPequenos, 1)
            if ($encontrados -gt 0 -and $handlesGrandes[0] -ne [IntPtr]::Zero) {
                $iconoGdi = [System.Drawing.Icon]::FromHandle($handlesGrandes[0])
            } else {
                # Respaldo si el índice exacto no dio nada
                $iconoGdi = [System.Drawing.Icon]::ExtractAssociatedIcon($rutaFichero)
            }
        }
        if (-not $iconoGdi) { return $null }
        $bitmap = $iconoGdi.ToBitmap()
        $memoria = New-Object System.IO.MemoryStream
        $bitmap.Save($memoria, [System.Drawing.Imaging.ImageFormat]::Png)
        $memoria.Position = 0
        $imagenWpf = New-Object System.Windows.Media.Imaging.BitmapImage
        $imagenWpf.BeginInit()
        $imagenWpf.StreamSource = $memoria
        $imagenWpf.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $imagenWpf.EndInit()
        $imagenWpf.Freeze()
        if ($handlesGrandes -and $handlesGrandes[0] -ne [IntPtr]::Zero) {
            [void][AytoIconHelper.IconHelper]::DestroyIcon($handlesGrandes[0])
        }
        return $imagenWpf
    } catch {
        return $null
    }
}

# Busca en el registro de Windows la ruta del icono ("DisplayIcon") que un
# programa YA INSTALADO tiene asociado, junto con el ÍNDICE exacto que
# indica (ej. "C:\ruta\app.dll,-101" -> ruta + índice -101). Funciona
# igual de bien para .exe que para .msi, porque una vez instalado Windows
# guarda esta ruta sin importar cómo se instaló.
function global:Obtener-RutaIconoDesdeRegistro($nombreBusqueda) {
    if (-not $nombreBusqueda) { return $null }
    $rutas = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($ruta in $rutas) {
        $items = Get-ItemProperty -Path $ruta -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "*$nombreBusqueda*" -and $_.DisplayIcon }
        if ($items) {
            $rutaIcono = ($items | Select-Object -First 1).DisplayIcon
            if ($rutaIcono -match '^(.*?)(?:,\s*(-?\d+))?$') {
                $rutaLimpia = $matches[1].Trim('"')
                $indice = if ($matches[2]) { [int]$matches[2] } else { 0 }
                if (Test-Path $rutaLimpia) { return @{ Ruta = $rutaLimpia; Indice = $indice } }
            }
        }
    }
    return $null
}

function global:Leer-InfoInstalador($rutaFichero) {
    if (-not $rutaFichero -or -not (Test-Path $rutaFichero)) { return $null }
    $ext = [System.IO.Path]::GetExtension($rutaFichero).ToLower()

    if ($ext -eq ".msi") {
        try {
            $installer = New-Object -ComObject WindowsInstaller.Installer
            $db = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @($rutaFichero, 0))
            $view = $db.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $db,
                @("SELECT Property, Value FROM Property WHERE Property IN ('ProductCode','ProductVersion','ProductName')"))
            $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null) | Out-Null
            $datos = @{}
            while ($true) {
                $rec = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
                if (-not $rec) { break }
                $prop = $rec.GetType().InvokeMember("StringData", "GetProperty", $null, $rec, 1)
                $val  = $rec.GetType().InvokeMember("StringData", "GetProperty", $null, $rec, 2)
                $datos[$prop] = $val
            }
            return @{ ProductCode = $datos['ProductCode']; ProductVersion = $datos['ProductVersion']; ProductName = $datos['ProductName'] }
        } catch {
            return $null
        }
    } elseif ($ext -eq ".exe") {
        try {
            $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($rutaFichero)
            $version = if ($vi.ProductVersion) { $vi.ProductVersion.Trim() } else { $vi.FileVersion }
            return @{ ProductCode = $null; ProductVersion = $version; ProductName = $vi.ProductName }
        } catch {
            return $null
        }
    }
    return $null   # .bat u otros formatos: no tienen metadatos de versión legibles
}

# Consulta winget para saber si un paquete está instalado y si hay versión más
# reciente disponible. Devuelve @{ Instalado; VersionInstalada; Actualizable }
# NOTA IMPORTANTE: "winget list --id X --exact" ha demostrado ser poco fiable
# para saber si algo está instalado (confirmado en pruebas reales: a veces no
# encuentra programas que SÍ están instalados con ese mismo Id, sobre todo en
# ediciones en español donde winget no logra correlacionar el registro con su
# catálogo). Por eso "instalado" se comprueba por el registro de Windows
# (igual que los programas "vivos"), y winget se usa solo para la pregunta
# secundaria de "¿hay una versión más nueva?" — si winget no sabe responder
# a eso, simplemente no ofrecemos "Actualizar" (mejor un falso negativo aquí
# que un falso "no está instalado" que invite a reinstalar innecesariamente).
# Lista de actualizaciones pendientes según winget, calculada UNA SOLA VEZ
# (no una vez por programa, que era lentísimo: "winget upgrade" es de las
# operaciones más lentas de winget porque consulta el catálogo online).
function global:Obtener-ActualizacionesWingetPendientes() {
    if ($null -ne $script:CacheActualizacionesWinget) { return $script:CacheActualizacionesWinget }
    $script:CacheActualizacionesWinget = ""
    if (-not $MODO_REAL) { return $script:CacheActualizacionesWinget }
    try {
        $salida = winget upgrade --accept-source-agreements 2>$null
        $script:CacheActualizacionesWinget = $salida -join "`n"
    } catch {
        # Sin conexión o winget no responde: nos quedamos sin saber qué
        # tiene actualización pendiente, no pasa nada, no se ofrecerá "Actualizar".
    }
    return $script:CacheActualizacionesWinget
}

function global:Obtener-EstadoWinget($prog, $idWinget) {
    $resultado = @{ Instalado = $false; Actualizable = $false }
    if (-not $MODO_REAL) { return $resultado }   # en simulación no consultamos nada real

    $nombreBusqueda = if ($prog.nombre_registro) { $prog.nombre_registro } else { $prog.nombre }
    $versionInstalada = Obtener-VersionInstaladaRegistro $nombreBusqueda
    if (-not $versionInstalada) { return $resultado }
    $resultado.Instalado = $true

    $textoActualizaciones = Obtener-ActualizacionesWingetPendientes
    $resultado.Actualizable = $textoActualizaciones -match [regex]::Escape($idWinget)
    return $resultado
}

# Determina el estado (Instalar / Actualizar / Instalado) de un programa,
# leyendo siempre los datos directamente del fichero real, nunca de un
# campo escrito a mano que se pueda quedar desactualizado.
# Extrae un número de versión (ej. "153.0.1") del propio NOMBRE del fichero.
# Útil cuando el metadato interno del instalador no es fiable (confirmado
# con Firefox: el .exe trae "18.05" en su ProductVersion interno, un dato
# que no tiene nada que ver con la versión real, que sí aparece en el
# nombre del fichero: "Firefox Setup 153.0.1.exe").
function global:Extraer-VersionDeNombreFichero($nombreFichero) {
    if ($nombreFichero -match "(\d+(?:\.\d+){1,3})") {
        return $matches[1]
    }
    return $null
}

function global:Obtener-EstadoPrograma($prog, $cfg) {
    if ($cfg.tipo -eq "winget") {
        $info = Obtener-EstadoWinget $prog $cfg.id_winget
        if (-not $info.Instalado) { return "instalar" }
        if ($info.Actualizable) { return "actualizar" }
        return "instalado"
    }

    if ($cfg.tipo -ne "instalador_vivo") {
        return "instalar"   # versionado_local: se deja siempre en Instalar, el usuario elige versión a mano
    }

    $carpetaCompleta = Join-Path $RutaBase $cfg.ruta
    $archivo = Obtener-InstaladorEnCarpeta $carpetaCompleta
    if (-not $archivo) { return "instalar" }

    # Intento de leer metadatos del propio fichero (puede fallar en silencio,
    # sobre todo la lectura de .msi vía COM, así que NUNCA dependemos solo de
    # esto: siempre hay un respaldo por nombre más abajo).
    $infoArchivo = Leer-InfoInstalador $archivo

    # Si el catálogo marca este programa como de metadato interno poco
    # fiable, sustituimos su ProductVersion por el número que aparezca en
    # el propio nombre del fichero (más fiable en estos casos concretos).
    if ($prog.version_desde_nombre_fichero) {
        $versionDelNombre = Extraer-VersionDeNombreFichero ([System.IO.Path]::GetFileName($archivo))
        if ($versionDelNombre) {
            if (-not $infoArchivo) { $infoArchivo = @{} }
            $infoArchivo.ProductVersion = $versionDelNombre
        }
    }

    $versionInstalada = $null
    $compararConVersionArchivo = $true   # si acabamos usando el nombre del catálogo como respaldo, no comparamos versión exacta

    if ($infoArchivo -and $infoArchivo.ProductCode) {
        # MSI con lectura correcta: comprobación exacta por ProductCode
        $versionInstalada = Obtener-VersionPorProductCode $infoArchivo.ProductCode
    }

    if (-not $versionInstalada) {
        # Probamos TODOS los nombres candidatos en cascada, no solo el primero
        # que exista: el "ProductName" del propio fichero a veces es el del
        # instalador/stub (ej. "Google Installer"), no el del programa real,
        # así que aunque exista hay que seguir probando con los demás.
        $candidatos = @()
        if ($infoArchivo -and $infoArchivo.ProductName) { $candidatos += $infoArchivo.ProductName }
        if ($prog.nombre_registro) { $candidatos += $prog.nombre_registro }
        $candidatos += $prog.nombre

        foreach ($candidato in $candidatos) {
            $versionInstalada = Obtener-VersionInstaladaRegistro $candidato $prog.arquitectura
            if ($versionInstalada) {
                # Si el nombre que ha funcionado NO es el que venía del propio
                # fichero, no podemos fiarnos de comparar contra su ProductVersion
                # (puede ser la versión de un stub/instalador, no del programa real)
                $compararConVersionArchivo = ($infoArchivo -and $candidato -eq $infoArchivo.ProductName)
                break
            }
        }
    }

    if (-not $versionInstalada) { return "instalar" }

    # Programas que se autoactualizan solos (ej. agentes de seguridad):
    # no comparamos versión exacta, solo si ya está presente.
    if ($prog.auto_actualizable) { return "instalado" }

    if (-not $compararConVersionArchivo -or -not $infoArchivo.ProductVersion) { return "instalado" }
    if ($versionInstalada -eq $infoArchivo.ProductVersion) { return "instalado" }
    return "actualizar"
}

# Pinta un botón de "Instalar" según el estado (instalar/actualizar/instalado).
# Reutilizada tanto al construir la lista como al refrescar tras una instalación.
function global:Aplicar-EstadoBoton($boton, $estado) {
    switch ($estado) {
        "instalado" {
            $boton.Content = "Instalado ✓"
            $boton.Background = "#2a2a2a"
            $boton.Foreground = "#888"
            $boton.IsEnabled = $false
        }
        "actualizar" {
            $boton.Content = "Actualizar"
            $boton.Background = "#E24B4A"
            $boton.Foreground = "White"
            $boton.IsEnabled = $true
        }
        default {
            $boton.Content = "Instalar"
            $boton.Background = "#141414"
            $boton.Foreground = "White"
            $boton.IsEnabled = $true
        }
    }
}

function global:Mostrar-Programas($departamento) {
    $PanelProgramas.Children.Clear()
    Set-Estado "Comprobando versiones instaladas..."

    # Referencias a {Boton, Programa, Config} de TODO lo que se pinte en esta
    # pantalla, para que "Instalar todo lo que falta" pueda recorrerlas luego.
    $script:ProgramasEnPantalla = @()

    # Fila propia para "Instalar todo lo que falta" + modo selección, como
    # primer elemento de la lista (no compite por espacio con la cabecera).
    $script:ModoSeleccion = $false

    $FilaInstalarTodo = New-Object System.Windows.Controls.DockPanel
    $FilaInstalarTodo.Margin = "0,0,0,15"

    $script:BtnInstalarTodo = New-Object System.Windows.Controls.Button
    $script:BtnInstalarTodo.Content = "Instalar todo"
    $script:BtnInstalarTodo.Width = 200
    $script:BtnInstalarTodo.Height = 34
    $script:BtnInstalarTodo.Background = "#E24B4A"
    $script:BtnInstalarTodo.Foreground = "White"
    [System.Windows.Controls.DockPanel]::SetDock($script:BtnInstalarTodo, "Right")
    $script:BtnInstalarTodo.Add_Click({ Instalar-Todo-EnPantalla })
    $FilaInstalarTodo.Children.Add($script:BtnInstalarTodo)

    $script:BtnElegir = New-Object System.Windows.Controls.Button
    $script:BtnElegir.Content = "Elegir qué instalar"
    $script:BtnElegir.Width = 160
    $script:BtnElegir.Height = 34
    $script:BtnElegir.Margin = "0,0,10,0"
    $script:BtnElegir.Background = "#232323"
    $script:BtnElegir.Foreground = "White"
    [System.Windows.Controls.DockPanel]::SetDock($script:BtnElegir, "Right")
    $script:BtnElegir.Add_Click({ Alternar-ModoSeleccion })
    $FilaInstalarTodo.Children.Add($script:BtnElegir)

    $script:BtnInstalarSeleccion = New-Object System.Windows.Controls.Button
    $script:BtnInstalarSeleccion.Content = "Instalar selección (0)"
    $script:BtnInstalarSeleccion.Width = 190
    $script:BtnInstalarSeleccion.Height = 34
    $script:BtnInstalarSeleccion.Margin = "0,0,10,0"
    $script:BtnInstalarSeleccion.Background = "#E24B4A"
    $script:BtnInstalarSeleccion.Foreground = "White"
    $script:BtnInstalarSeleccion.Visibility = "Collapsed"
    [System.Windows.Controls.DockPanel]::SetDock($script:BtnInstalarSeleccion, "Right")
    $script:BtnInstalarSeleccion.Add_Click({ Instalar-Seleccion-EnPantalla })
    $FilaInstalarTodo.Children.Add($script:BtnInstalarSeleccion)

    $script:BtnCancelarSeleccion = New-Object System.Windows.Controls.Button
    $script:BtnCancelarSeleccion.Content = "Cancelar"
    $script:BtnCancelarSeleccion.Width = 100
    $script:BtnCancelarSeleccion.Height = 34
    $script:BtnCancelarSeleccion.Margin = "0,0,10,0"
    $script:BtnCancelarSeleccion.Background = "#232323"
    $script:BtnCancelarSeleccion.Foreground = "White"
    $script:BtnCancelarSeleccion.Visibility = "Collapsed"
    [System.Windows.Controls.DockPanel]::SetDock($script:BtnCancelarSeleccion, "Right")
    $script:BtnCancelarSeleccion.Add_Click({ Alternar-ModoSeleccion })
    $FilaInstalarTodo.Children.Add($script:BtnCancelarSeleccion)

    [void]$PanelProgramas.Children.Add($FilaInstalarTodo)

    # Se desactiva toda la ventana mientras se comprueban versiones: así,
    # cualquier clic que el usuario dé por impaciencia durante la espera se
    # IGNORA de verdad (WPF no entrega eventos a una ventana desactivada),
    # en vez de quedar "en cola" y dispararse luego sobre el botón que
    # termine apareciendo en esa misma posición de pantalla.
    $PanelContenido.IsEnabled = $false
    Mostrar-Progreso
    [System.Windows.Forms.Application]::DoEvents()

    # La caché de "qué tiene actualización pendiente" se reinicia en cada
    # visita a un departamento (para no quedarse con datos viejos de sesión),
    # pero se reutiliza entre los distintos programas de ESTA misma pantalla
    # en vez de consultar winget una vez por programa (muy lento).
    $script:CacheActualizacionesWinget = $null

    # Solo programas de este departamento QUE TENGAN configuración para el modo actual
    $ProgramasDep = $Catalogo.programas | Where-Object {
        $_.departamento -eq $departamento -and $null -ne $_.($script:ModoActual)
    }

    foreach ($prog in $ProgramasDep) {

        # Config específica del modo activo (online u offline) para este programa
        $cfg = $prog.($script:ModoActual)

        $Card = New-Object System.Windows.Controls.Border
        $Card.Background = "#232323"
        $Card.CornerRadius = "8"
        $Card.Margin = "0,0,0,10"
        $Card.Padding = "15"
        $Card.BorderBrush = "#333"
        $Card.BorderThickness = "1"

        $Row = New-Object System.Windows.Controls.Grid
        $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = "Auto"
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = "*"
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = "Auto"
        $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = "Auto"
        $Row.ColumnDefinitions.Add($col0); $Row.ColumnDefinitions.Add($col1); $Row.ColumnDefinitions.Add($col2); $Row.ColumnDefinitions.Add($col3)

        # Casilla de selección, oculta salvo en "modo elegir"
        $Casilla = New-Object System.Windows.Controls.CheckBox
        $Casilla.VerticalAlignment = "Center"
        $Casilla.Margin = "0,0,15,0"
        $Casilla.Visibility = "Collapsed"
        [System.Windows.Controls.Grid]::SetColumn($Casilla, 0)
        $Row.Children.Add($Casilla)

        $ColumnaTitulo = New-Object System.Windows.Controls.StackPanel
        $ColumnaTitulo.Orientation = "Vertical"
        $ColumnaTitulo.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($ColumnaTitulo, 1)

        # Icono: se prueba primero el del registro (funciona igual para
        # .exe y .msi UNA VEZ instalado, mucho más fiable), y si no está
        # disponible (aún no instalado, o sin DisplayIcon), se cae al
        # icono incrustado en el instalador offline local si es un .exe.
        $IconoReal = $null
        $nombreBusquedaIcono = if ($prog.nombre_registro) { $prog.nombre_registro } else { $prog.nombre }
        $rutaIconoRegistro = Obtener-RutaIconoDesdeRegistro $nombreBusquedaIcono
        if ($rutaIconoRegistro) {
            $IconoReal = Obtener-IconoDesdeExe $rutaIconoRegistro.Ruta $rutaIconoRegistro.Indice
        }
        if (-not $IconoReal -and $prog.offline -and $prog.offline.tipo -eq "instalador_vivo") {
            $carpetaOffline = Join-Path $RutaBase $prog.offline.ruta
            $archivoOffline = Buscar-ExeParaIcono $carpetaOffline
            if ($archivoOffline) { $IconoReal = Obtener-IconoDesdeExe $archivoOffline }
        }

        $FilaTitulo = New-Object System.Windows.Controls.StackPanel
        $FilaTitulo.Orientation = "Horizontal"

        if ($IconoReal) {
            $ImagenIcono = New-Object System.Windows.Controls.Image
            $ImagenIcono.Source = $IconoReal
            $ImagenIcono.Width = 22
            $ImagenIcono.Height = 22
            $ImagenIcono.Margin = "0,0,8,0"
            $FilaTitulo.Children.Add($ImagenIcono)
        }

        $Titulo = New-Object System.Windows.Controls.TextBlock
        $Titulo.Text = if ($IconoReal) { $prog.nombre } else { "$($prog.icono)  $($prog.nombre)" }
        $Titulo.FontSize = 16
        $Titulo.FontWeight = "SemiBold"
        $Titulo.Foreground = "#f0f0f0"
        $Titulo.VerticalAlignment = "Center"
        $FilaTitulo.Children.Add($Titulo)

        $ColumnaTitulo.Children.Add($FilaTitulo)

        $Row.Children.Add($ColumnaTitulo)

        # Si es versionado_local, añadimos un combo de versiones
        $ComboVersion = $null
        if ($cfg.tipo -eq "versionado_local") {
            $ComboVersion = New-Object System.Windows.Controls.ComboBox
            $ComboVersion.Width = 130
            $ComboVersion.Margin = "0,0,10,0"
            $versiones = Obtener-VersionesDisponibles $cfg.ruta
            foreach ($v in $versiones) { [void]$ComboVersion.Items.Add($v) }
            if ($ComboVersion.Items.Count -gt 0) { $ComboVersion.SelectedIndex = 0 }
            [System.Windows.Controls.Grid]::SetColumn($ComboVersion, 2)
            $Row.Children.Add($ComboVersion)
        }

        $BtnInstalar = New-Object System.Windows.Controls.Button
        $BtnInstalar.Width = 110
        $BtnInstalar.Height = 32
        [System.Windows.Controls.Grid]::SetColumn($BtnInstalar, 3)

        $estado = Obtener-EstadoPrograma $prog $cfg
        Aplicar-EstadoBoton $BtnInstalar $estado

        $script:ProgramasEnPantalla += @{ Boton = $BtnInstalar; Prog = $prog; Cfg = $cfg; Combo = $ComboVersion; Casilla = $Casilla }

        # Closure con variables capturadas correctamente
        $nombreLocal = $prog.nombre
        $progLocal = $prog
        $cfgLocal = $cfg
        $comboLocal = $ComboVersion
        $BtnInstalar.Add_Click({
            # Bloquear el botón de inmediato para evitar dobles clics mientras instala
            $this.IsEnabled = $false
            $this.Content = "Instalando..."
            $this.Background = "#555555"
            $this.Foreground = "White"

            switch ($cfgLocal.tipo) {
                "winget" {
                    Instalar-Winget $cfgLocal.id_winget $nombreLocal $cfgLocal.winget_args
                }
                "instalador_vivo" {
                    Instalar-Vivo $cfgLocal.ruta $cfgLocal.flags $nombreLocal
                }
                "versionado_local" {
                    $versionSeleccionada = $comboLocal.SelectedItem
                    Instalar-VersionadoLocal $cfgLocal.ruta $cfgLocal.flags $versionSeleccionada $nombreLocal
                }
            }
            # Tras instalar, se vuelve a comprobar el estado real de ESTE
            # programa y se refresca el propio botón (sin recargar toda la
            # lista, así no se pierde el scroll ni se repiten comprobaciones
            # de los demás programas).
            Start-Sleep -Milliseconds 800   # pequeño margen para que el registro se actualice del todo
            $estadoNuevo = Obtener-EstadoPrograma $progLocal $cfgLocal
            Aplicar-EstadoBoton $this $estadoNuevo
        }.GetNewClosure())

        $Row.Children.Add($BtnInstalar)
        $Card.Child = $Row
        [void]$PanelProgramas.Children.Add($Card)
    }

    $PanelDepartamentos.Visibility = "Collapsed"
    $ScrollProgramas.Visibility = "Visible"
    $BtnVolver.Visibility = "Visible"
    Set-Estado "Departamento: $departamento ($($ProgramasDep.Count) programas, modo $($script:ModoActual))"
    Ocultar-Progreso
    $PanelContenido.IsEnabled = $true
}


# ------------------- CONSTRUCCIÓN BOTONES DEPARTAMENTO -------------------
foreach ($dep in $Catalogo.departamentos) {
    $Btn = New-Object System.Windows.Controls.Button
    $Btn.Content = $dep
    $Btn.Width = 220
    $Btn.Height = 90
    $Btn.Margin = "10"
    $Btn.FontSize = 16
    $Btn.Background = "#232323"
    $Btn.Foreground = "#f0f0f0"
    $Btn.BorderBrush = "#E24B4A"
    $Btn.BorderThickness = "2"

    $depLocal = $dep
    $Btn.Add_Click({ Mostrar-Programas $depLocal }.GetNewClosure())

    [void]$PanelDepartamentos.Children.Add($Btn)
}

$BtnVolver.Add_Click({
    $ScrollProgramas.Visibility = "Collapsed"
    $BtnVolver.Visibility = "Collapsed"
    $PanelDepartamentos.Visibility = "Visible"
    Set-Estado "Modo: $($script:ModoActual). Selecciona un departamento."
})

# Recorre todos los programas de la pantalla actual e instala/actualiza los
# que no estén ya en "Instalado ✓". Se salta los de tipo versionado_local
# (necesitan que el usuario elija versión a mano) y, sobre la marcha, va
# refrescando cada botón individual igual que si se hubiera pulsado a mano.
# Comprueba si ESTE equipo está unido a un dominio de Windows. Es una
# consulta local (no necesita contactar con el controlador de dominio),
# así que es rápida y fiable incluso sin conectividad de red.
function global:Obtener-EstaEnDominio() {
    try {
        return [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
    } catch {
        return $false   # si no se puede determinar, por seguridad asumimos que no
    }
}

# Renombra este PC y lo une al dominio del Ayto. Pide el nombre nuevo y
# las credenciales EN EL MOMENTO (nunca se guardan en ningún fichero).
# Requiere reiniciar para que el cambio se aplique del todo; se avisa al
# usuario al final en vez de reiniciar solo.
function global:Unir-Al-Dominio() {
    $DominioAyto = "ad.ayamonte.es"

    $nuevoNombre = [Microsoft.VisualBasic.Interaction]::InputBox(
        "¿Qué nombre quieres ponerle a este equipo?",
        "Unir al dominio",
        $env:COMPUTERNAME)
    if (-not $nuevoNombre) { return }

    $confirmacion = [System.Windows.MessageBox]::Show(
        "Se va a renombrar este equipo a '$nuevoNombre' y unirlo al dominio '$DominioAyto'.`n`nA continuación se pedirán las credenciales de un usuario con permiso para unir equipos al dominio (no se guardan en ningún sitio).`n`n¿Continuar?",
        "Confirmar unión al dominio", "YesNo", "Question")
    if ($confirmacion -ne "Yes") { return }

    $credenciales = Get-Credential -Message "Usuario con permiso para unir equipos al dominio $DominioAyto"
    if (-not $credenciales) { return }

    Set-Estado "Uniendo al dominio y renombrando a '$nuevoNombre'... esto puede tardar un poco."
    Mostrar-Progreso
    $PanelContenido.IsEnabled = $false
    [System.Windows.Forms.Application]::DoEvents()

    try {
        Add-Computer -DomainName $DominioAyto -NewName $nuevoNombre -Credential $credenciales -Force -ErrorAction Stop
        Ocultar-Progreso
        $PanelContenido.IsEnabled = $true
        $BtnUnirDominio.Visibility = "Collapsed"
        [System.Windows.MessageBox]::Show(
            "Hecho. El equipo se llamará '$nuevoNombre' y quedará unido al dominio en cuanto reinicies.`n`nReinicia el PC cuando puedas para completarlo.",
            "Unión al dominio completada", "OK", "Information")
        Set-Estado "Unido al dominio como '$nuevoNombre'. PENDIENTE DE REINICIAR."
    } catch {
        Ocultar-Progreso
        $PanelContenido.IsEnabled = $true
        [System.Windows.MessageBox]::Show(
            "No se pudo unir al dominio:`n$($_.Exception.Message)",
            "Error", "OK", "Error")
        Set-Estado "⚠ Fallo al unir al dominio."
    }
}

# Activa/desactiva el "modo elegir": muestra u oculta las casillas de cada
# programa y cambia qué botones se ven arriba (Instalar todo/Elegir <-> 
# Instalar selección/Cancelar).
function global:Alternar-ModoSeleccion() {
    $script:ModoSeleccion = -not $script:ModoSeleccion

    if ($script:ModoSeleccion) {
        $script:BtnInstalarTodo.Visibility = "Collapsed"
        $script:BtnElegir.Visibility = "Collapsed"
        $script:BtnInstalarSeleccion.Visibility = "Visible"
        $script:BtnCancelarSeleccion.Visibility = "Visible"
        $script:BtnInstalarSeleccion.IsEnabled = $false
        $script:BtnInstalarSeleccion.Content = "Instalar selección (0)"

        foreach ($item in $script:ProgramasEnPantalla) {
            $estado = Obtener-EstadoPrograma $item.Prog $item.Cfg
            if ($estado -eq "instalado") {
                # Ya instalado: no tiene sentido poder marcarlo
                continue
            }
            $item.Boton.Visibility = "Collapsed"
            $item.Casilla.IsChecked = $false
            $item.Casilla.Visibility = "Visible"
            $item.Casilla.Add_Click({ Actualizar-ContadorSeleccion })
        }
    } else {
        $script:BtnInstalarTodo.Visibility = "Visible"
        $script:BtnElegir.Visibility = "Visible"
        $script:BtnInstalarSeleccion.Visibility = "Collapsed"
        $script:BtnCancelarSeleccion.Visibility = "Collapsed"

        foreach ($item in $script:ProgramasEnPantalla) {
            $item.Casilla.Visibility = "Collapsed"
            $item.Boton.Visibility = "Visible"
        }
    }
}

# Se llama cada vez que se marca/desmarca una casilla: actualiza el
# contador del botón "Instalar selección (N)" y lo activa/desactiva.
function global:Actualizar-ContadorSeleccion() {
    $marcados = @($script:ProgramasEnPantalla | Where-Object { $_.Casilla.Visibility -eq "Visible" -and $_.Casilla.IsChecked })
    $script:BtnInstalarSeleccion.Content = "Instalar selección ($($marcados.Count))"
    $script:BtnInstalarSeleccion.IsEnabled = ($marcados.Count -gt 0)
}

# Instala únicamente los programas marcados con la casilla.
function global:Instalar-Seleccion-EnPantalla() {
    $enDominio = Obtener-EstaEnDominio

    $marcados = @($script:ProgramasEnPantalla | Where-Object { $_.Casilla.Visibility -eq "Visible" -and $_.Casilla.IsChecked })
    $saltadosPorDominio = @($marcados | Where-Object { $_.Prog.requiere_dominio -and -not $enDominio })
    $aInstalar = @($marcados | Where-Object { -not $_.Prog.requiere_dominio -or $enDominio })

    if ($aInstalar.Count -eq 0) {
        if ($saltadosPorDominio.Count -gt 0) {
            Set-Estado "Los seleccionados requieren dominio; instálalos a mano cuando el equipo ya esté unido."
        }
        Alternar-ModoSeleccion
        return
    }

    $PanelContenido.IsEnabled = $false
    $script:BtnInstalarSeleccion.IsEnabled = $false
    $script:BtnInstalarSeleccion.Content = "Instalando..."
    $script:BtnCancelarSeleccion.IsEnabled = $false

    $indice = 0
    foreach ($item in $aInstalar) {
        $indice++
        Set-Estado "Instalando $indice de $($aInstalar.Count): $($item.Prog.nombre)..."
        $item.Casilla.Visibility = "Collapsed"
        $item.Boton.Visibility = "Visible"
        $item.Boton.IsEnabled = $false
        $item.Boton.Content = "Instalando..."
        $item.Boton.Background = "#555555"
        $item.Boton.Foreground = "White"
        [System.Windows.Forms.Application]::DoEvents()

        switch ($item.Cfg.tipo) {
            "winget" {
                Instalar-Winget $item.Cfg.id_winget $item.Prog.nombre $item.Cfg.winget_args
            }
            "instalador_vivo" {
                Instalar-Vivo $item.Cfg.ruta $item.Cfg.flags $item.Prog.nombre
            }
        }

        Start-Sleep -Milliseconds 800   # pequeño margen para que el registro se actualice del todo
        $estadoNuevo = Obtener-EstadoPrograma $item.Prog $item.Cfg
        Aplicar-EstadoBoton $item.Boton $estadoNuevo
    }

    $PanelContenido.IsEnabled = $true
    if ($saltadosPorDominio.Count -gt 0) {
        Set-Estado "Instalación completada ($($aInstalar.Count) programas). Quedan $($saltadosPorDominio.Count) que requieren dominio."
    } else {
        Set-Estado "Instalación completada ($($aInstalar.Count) programas)."
    }

    Alternar-ModoSeleccion
}

function global:Instalar-Todo-EnPantalla() {
    $enDominio = Obtener-EstaEnDominio

    $saltadosPorDominio = $script:ProgramasEnPantalla | Where-Object {
        $_.Prog.requiere_dominio -and -not $enDominio -and (Obtener-EstadoPrograma $_.Prog $_.Cfg) -ne "instalado"
    }

    $pendientes = $script:ProgramasEnPantalla | Where-Object {
        (Obtener-EstadoPrograma $_.Prog $_.Cfg) -ne "instalado" -and
        $_.Cfg.tipo -ne "versionado_local" -and
        (-not $_.Prog.requiere_dominio -or $enDominio)
    }

    if ($pendientes.Count -eq 0) {
        if ($saltadosPorDominio.Count -gt 0) {
            Set-Estado "Nada más que instalar en cadena. Quedan $($saltadosPorDominio.Count) que requieren dominio: instálalos a mano cuando el equipo ya esté unido."
        } else {
            Set-Estado "No hay nada pendiente: todo lo de esta pantalla ya está instalado."
        }
        return
    }

    $PanelContenido.IsEnabled = $false
    $script:BtnInstalarTodo.IsEnabled = $false
    $script:BtnInstalarTodo.Content = "Instalando..."

    # Se marcan TODOS los pendientes como "En cola" y se desactivan uno a
    # uno de forma explícita (no solo confiando en que el panel entero esté
    # desactivado) — así, aunque algo fallara con la desactivación en
    # cascada, cada botón individual sigue bloqueado por sí mismo.
    foreach ($item in $pendientes) {
        $item.Boton.IsEnabled = $false
        $item.Boton.Content = "En cola..."
        $item.Boton.Background = "#3a3a3a"
        $item.Boton.Foreground = "#999"
    }
    [System.Windows.Forms.Application]::DoEvents()

    $indice = 0
    foreach ($item in $pendientes) {
        $indice++
        Set-Estado "Instalando $indice de $($pendientes.Count): $($item.Prog.nombre)..."
        $item.Boton.Content = "Instalando..."
        $item.Boton.Background = "#555555"
        $item.Boton.Foreground = "White"
        [System.Windows.Forms.Application]::DoEvents()

        switch ($item.Cfg.tipo) {
            "winget" {
                Instalar-Winget $item.Cfg.id_winget $item.Prog.nombre $item.Cfg.winget_args
            }
            "instalador_vivo" {
                Instalar-Vivo $item.Cfg.ruta $item.Cfg.flags $item.Prog.nombre
            }
        }

        Start-Sleep -Milliseconds 800   # pequeño margen para que el registro se actualice del todo
        $estadoNuevo = Obtener-EstadoPrograma $item.Prog $item.Cfg
        Aplicar-EstadoBoton $item.Boton $estadoNuevo
    }

    $script:BtnInstalarTodo.Content = "Instalar todo lo que falta"
    $script:BtnInstalarTodo.IsEnabled = $true
    $PanelContenido.IsEnabled = $true
    if ($saltadosPorDominio.Count -gt 0) {
        Set-Estado "Instalación en cadena completada ($($pendientes.Count) programas). Quedan $($saltadosPorDominio.Count) que requieren dominio: instálalos a mano cuando el equipo ya esté unido."
    } else {
        Set-Estado "Instalación en cadena completada ($($pendientes.Count) programas)."
    }
}



$BtnUnirDominio.Add_Click({ Unir-Al-Dominio })

# Solo se muestra el botón de unir al dominio si el equipo AÚN no lo está
if (-not (Obtener-EstaEnDominio)) {
    $BtnUnirDominio.Visibility = "Visible"
}

# ------------------- LANZAR -------------------
$Window.ShowDialog() | Out-Null

<#
    ---------------------------------------------------------
    CÓMO CONVERTIR ESTE SCRIPT EN UN .EXE
    ---------------------------------------------------------
    1. Instalar el módulo PS2EXE (una sola vez, con internet):
         Install-Module -Name ps2exe -Scope CurrentUser

    2. Generar el ejecutable:

        powershell -ExecutionPolicy Bypass

         Invoke-ps2exe -inputFile "Launcher.ps1" -outputFile "LauncherAyto.exe" `
             -noConsole -iconFile "logo_ayto.ico"

    3. IMPORTANTE para el pen: copia el .exe + catalog.json + carpeta "apps"
       TODOS JUNTOS en la raíz del pen. Gracias a $PSScriptRoot, funcionará
       sin importar qué letra de unidad (D:, E:, F:...) le asigne Windows
       al conectarlo en cada equipo.

    4. Mantenimiento del pen offline: cuando salga una versión nueva de
       Chrome/Firefox/etc., descargad el instalador una vez y sobreescribid
       el fichero correspondiente en apps\<programa>\ (mismo nombre de
       fichero que indica catalog.json). No hace falta tocar el script.
#>
