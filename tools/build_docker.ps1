## Exporta el cliente Web y construye la imagen Docker (ADR 016).
## Uso: pwsh tools/build_docker.ps1 [-Tag rpg-mapping-web:latest] [-NoExport]
## $env:GODOT apunta al ejecutable de Godot (si no, se busca el habitual).
param(
	[string]$Tag = "rpg-mapping-web:latest",
	[switch]$NoExport
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $NoExport) {
	$godot = $env:GODOT
	if (-not $godot) {
		$godot = Join-Path $env:LOCALAPPDATA "Programs\Godot\Godot_v4.7.2-stable_win64_console.exe"
	}
	New-Item -ItemType Directory -Force build/web | Out-Null
	& $godot --headless --path project --export-release "Web" ../build/web/index.html
	if ($LASTEXITCODE -ne 0) { throw "La exportación Web falló ($LASTEXITCODE)" }
	# Godot reescribe project.godot al exportar: se deja como estaba.
	git checkout -- project/project.godot 2>$null
}
if (-not (Test-Path build/web/index.html)) { throw "Falta build/web/index.html" }

docker build -f docker/Dockerfile -t $Tag .
if ($LASTEXITCODE -ne 0) { throw "docker build falló ($LASTEXITCODE)" }
Write-Host "Imagen lista: $Tag"
