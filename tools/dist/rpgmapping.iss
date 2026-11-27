; Instalador de RPG Mapping para Windows (Inno Setup 6; ADR 046).
; Lo compila tools/build_dist.ps1 con:
;   ISCC /DAppVersion=<ver> /DSrcDir=<carpeta portable> /DOutDir=<salida> rpgmapping.iss
; Instalación por usuario (sin administrador): %LOCALAPPDATA%\Programs\RPG Mapping.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Identificador fijo: las versiones nuevas se instalan encima de la anterior.
AppId={{6C1B5E9A-3F7D-4B8E-9A21-52D4C0E7A1F3}
AppName=RPG Mapping
AppVersion={#AppVersion}
AppVerName=RPG Mapping {#AppVersion}
AppPublisher=RPG Mapping
DefaultDirName={autopf}\RPG Mapping
DefaultGroupName=RPG Mapping
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutDir}
OutputBaseFilename=RPGMapping-{#AppVersion}-windows-instalador
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\RPGMapping.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Si la app está abierta, el instalador pide cerrarla.
CloseApplications=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; La carpeta portable entera: el ejecutable, "web" (cliente de los jugadores,
; debe ir junto al .exe), LEEME y licencias.
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\RPG Mapping"; Filename: "{app}\RPGMapping.exe"
Name: "{autodesktop}\RPG Mapping"; Filename: "{app}\RPGMapping.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\RPGMapping.exe"; Description: "{cm:LaunchProgram,RPG Mapping}"; Flags: nowait postinstall skipifsilent
