# 🚀 Launcher de Software — Ayuntamiento de Ayamonte

Aplicación de escritorio para automatizar la instalación y actualización de software en los equipos del Ayuntamiento de Ayamonte, desarrollada como parte de mis prácticas en el departamento de Informática.

Sustituye el sistema anterior (notebook con apuntes a mano + pen drive con instaladores sueltos) por una interfaz gráfica con detección automática de lo que ya está instalado, instalación silenciosa en cadena, y soporte tanto para equipos con conexión a internet como para despliegues totalmente offline.

---

## ✨ Características

- **Interfaz WPF nativa** escrita en PowerShell — sin dependencias externas más allá de lo que ya trae Windows
- **Dos modos de instalación:**
  - 🌐 **ONLINE** — vía [winget](https://learn.microsoft.com/es-es/windows/package-manager/winget/), con detección de actualizaciones disponibles
  - 💾 **OFFLINE** — desde un pen drive, sin necesidad de internet
- **Detección automática de estado** (Instalar / Actualizar / Instalado ✓) leyendo directamente el registro de Windows y los metadatos de cada instalador (`ProductCode` de MSI, versión embebida en `.exe`...), sin depender de datos escritos a mano
- **Instalación en cadena** ("Instalar todo lo que falta") y **modo selección** con casillas para elegir programas concretos
- **Catálogo dirigido por JSON** — añadir o modificar programas no requiere tocar el código, solo el `catalog.json`
- **Iconos reales** extraídos de cada instalador o del registro de Windows, con respaldo a emoji cuando no es posible
- **Integración con agentes de seguridad corporativos** (FortiEDR, microCLAUDIA/CCN-CERT) y herramientas internas (AutoFirma, RustDesk con configuración propia del Ayuntamiento)
- **Unión al dominio integrada** — renombra el equipo y lo une al Active Directory pidiendo credenciales en el momento, sin almacenarlas nunca en disco
- **Versión "solo offline"** para equipos donde el EDR corporativo bloquea las conexiones de `winget`

---

## 🛠️ Stack técnico

- **PowerShell 5.1** + **WPF** (XAML embebido) para la interfaz
- **winget** para el modo online
- **ps2exe** para compilar a `.exe` autónomo
- Lectura de metadatos vía **COM (Windows Installer)** y **P/Invoke** (extracción de iconos por índice exacto con `ExtractIconEx`)

---

## 📁 Estructura del proyecto

> La carpeta `apps/` de abajo es **ilustrativa** — los instaladores reales no se incluyen en este repositorio (ver motivos más abajo).

```
├── Launcher_v3.ps1              # Versión completa (ONLINE + OFFLINE)
├── Launcher_Offline.ps1         # Versión solo OFFLINE (sin winget)
├── catalog.example.json         # Plantilla del catálogo (sin datos reales)
├── apps/                        # (no incluida) instaladores organizados por programa
│   └── rustdesk/
│       └── Instalar_RustDesk.ps1  # Wrapper: instala + configura + acceso directo
└── README.md
```

---

## ⚙️ Puesta en marcha

1. Copia `catalog.example.json` como `catalog.json` y rellena los datos reales de tu organización (servidores, API keys, etc. — **nunca subas este fichero con datos reales a un repositorio**)
2. Crea la carpeta `apps/` con una subcarpeta por programa, conteniendo el instalador correspondiente
3. Ejecuta con:
   ```powershell
   powershell -ExecutionPolicy Bypass -File Launcher_v3.ps1
   ```
4. Para compilar a `.exe` (requiere el módulo [`ps2exe`](https://www.powershellgallery.com/packages/ps2exe)):
   ```powershell
   Install-Module -Name ps2exe -Scope CurrentUser
   Invoke-ps2exe -inputFile "Launcher_v3.ps1" -outputFile "LauncherAyto.exe" -noConsole -requireAdmin -iconFile "icono.ico"
   ```

---

## 🔒 Sobre los datos sensibles

Este repositorio **no incluye** ningún dato real de la organización (API keys, IPs internas, credenciales). El `catalog.json` real y los scripts con configuración específica (servidores RustDesk, keys de microCLAUDIA...) se gestionan localmente y quedan fuera del control de versiones.

Tampoco se incluyen los **instaladores reales** (carpeta `apps/`): además de su tamaño, la mayoría son software de terceros con licencia propia (Adobe, WinRAR, Java...) que no es redistribuible libremente.

---

## 📌 Contexto

Proyecto desarrollado durante mis prácticas de FP (DAM/SMR) en el departamento de Informática del Ayuntamiento de Ayamonte, bajo la supervisión del administrador de sistemas. Lo comparto aquí como muestra de trabajo para portfolio — el código pertenece a la administración pública para la que fue desarrollado (Art. 97.4 LPI).

---

## 📄 Licencia

Repositorio con fines de portfolio personal. Uso del código sujeto a autorización del Ayuntamiento de Ayamonte.
