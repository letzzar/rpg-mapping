# Ejecuta los tests GUT en headless (Windows).
#
# Por qué existe: GUT ignora en silencio los scripts de test que no compilan
# (p. ej. por un aviso de tipado tratado como error) y aun así termina con
# "All tests passed" y código 0. Este script falla también en ese caso.
#
# Uso:  pwsh tools/run_tests.ps1 [-Dir res://tests/golden]
#       $env:GODOT = ruta al ejecutable de Godot (si no, se busca la portable).
param([string]$Dir = "res://tests")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT
if (-not $godot) { $godot = "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.2-stable_win64_console.exe" }
if (-not (Test-Path $godot)) { throw "No se encuentra Godot en '$godot'. Define `$env:GODOT." }

$project = Join-Path $root "project"
# Importar primero: registra class_name nuevos y genera las traducciones.
& $godot --headless --path $project --import 2>&1 | Out-Null
$out = & $godot --headless --path $project -s addons/gut/gut_cmdln.gd "-gdir=$Dir" -ginclude_subdirs -gexit 2>&1 | ForEach-Object { "$_" }
$code = $LASTEXITCODE
$out | Write-Output

$broken = $out | Select-String -Pattern 'SCRIPT ERROR|Parse Error|Ignoring script'
if ($broken) {
	Write-Error "Hay scripts con errores o ignorados por GUT:`n$($broken -join "`n")"
	exit 1
}
exit $code
