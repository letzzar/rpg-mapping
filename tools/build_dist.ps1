## Prepara el distribuible de Windows (ADR 046):
##   build/dist/RPG Mapping/                             carpeta portable (doble clic en el .exe)
##   build/dist/RPGMapping-<ver>-windows.zip             la misma carpeta comprimida
##   build/dist/RPGMapping-<ver>-windows-instalador.exe  instalador (Inno Setup 6)
## Uso: pwsh tools/build_dist.ps1 [-NoExport] [-NoInstaller]
## $env:GODOT apunta a Godot y $env:ISCC al compilador de Inno Setup (si no,
## se buscan en las rutas habituales). Sin Inno Setup solo sale el portable.
param(
	[switch]$NoExport,
	[switch]$NoInstaller
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$version = ((Select-String -Path project/project.godot -Pattern '^config/version="(.*)"').Matches[0].Groups[1].Value)
$dist = Join-Path $root "build/dist"
$app = Join-Path $dist "RPG Mapping"
$name = "RPGMapping-$version-windows"

if (-not $NoExport) {
	$godot = $env:GODOT
	if (-not $godot) {
		$godot = Join-Path $env:LOCALAPPDATA "Programs\Godot\Godot_v4.7.2-stable_win64_console.exe"
	}
	New-Item -ItemType Directory -Force build/web, build/win | Out-Null
	& $godot --headless --path project --export-release "Web" ../build/web/index.html
	if ($LASTEXITCODE -ne 0) { throw "La exportación Web falló ($LASTEXITCODE)" }
	& $godot --headless --path project --export-release "Windows Desktop" ../build/win/RPGMapping.exe
	if ($LASTEXITCODE -ne 0) { throw "La exportación de Windows falló ($LASTEXITCODE)" }
	# Godot reescribe project.godot al exportar: se deja como estaba.
	git checkout -- project/project.godot 2>$null
}
foreach ($f in @("build/web/index.html", "build/win/RPGMapping.exe")) {
	if (-not (Test-Path $f)) { throw "Falta $f" }
}

# Carpeta portable: el ejecutable (con el .pck dentro) y "web" a su lado, que
# es donde la busca la partida en red (NetHostPanel.find_web_root).
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force $app, (Join-Path $app "web") | Out-Null
Copy-Item build/win/RPGMapping.exe $app
Copy-Item build/web/* (Join-Path $app "web")
Copy-Item LICENSE (Join-Path $app "LICENSE.txt")
Set-Content -Path (Join-Path $app "VERSION.txt") -Value $version -Encoding utf8
(Get-Content tools/dist/LEEME.txt -Raw -Encoding utf8).Replace("{VERSION}", $version) |
	Set-Content -Path (Join-Path $app "LEEME.txt") -Encoding utf8 -NoNewline

# Licencias de terceros: el registro de assets y la atribución de cada perfil
# de reglas (su bloque "content").
$third = [System.Text.StringBuilder]::new()
[void]$third.AppendLine((Get-Content assets/LICENSES.md -Raw -Encoding utf8))
[void]$third.AppendLine("`n# Contenido de reglas`n")
foreach ($p in Get-ChildItem project/data/systems/*.json | Sort-Object Name) {
	$c = (Get-Content $p -Raw -Encoding utf8 | ConvertFrom-Json).content
	if ($null -ne $c) {
		[void]$third.AppendLine("## $($p.Name): $($c.source) ($($c.license))`n")
		[void]$third.AppendLine("$($c.attribution)`n")
	}
}
Set-Content -Path (Join-Path $app "LICENCIAS-TERCEROS.md") -Value $third.ToString() -Encoding utf8
Copy-Item project/models/kaykit/LICENSE-*.txt $app

# Zip con la carpeta "RPG Mapping" dentro (tar.exe de Windows escribe zip).
$zip = Join-Path $dist "$name.zip"
Push-Location $dist
tar.exe -a -cf "$name.zip" "RPG Mapping"
if ($LASTEXITCODE -ne 0) { throw "No se pudo crear el zip ($LASTEXITCODE)" }
Pop-Location
Write-Host "Portable: $zip"

if ($NoInstaller) { return }
if ($NoInstaller) { return }

# Instalador: Inno Setup, por usuario y sin administrador (PrivilegesRequired
# lowest), con accesos directos y desinstalador en "Aplicaciones instaladas".
$iscc = $env:ISCC
if (-not $iscc) {
	$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") |
		Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $iscc) {
	Write-Warning "No se encuentra Inno Setup 6 (ISCC.exe): solo se genera el portable."
	return
}
& $iscc /Q "/DAppVersion=$version" "/DSrcDir=$app" "/DOutDir=$dist" "/DIconFile=$root\project\export_icons\app.ico" tools/dist/rpgmapping.iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup falló ($LASTEXITCODE)" }
Write-Host "Instalador: $(Join-Path $dist "RPGMapping-$version-windows-instalador.exe")"
