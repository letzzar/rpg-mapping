#!/usr/bin/env sh
# Ejecuta los tests GUT en headless (Linux/macOS/CI). Ver run_tests.ps1 para
# el porqué: falla también si GUT ignora scripts que no compilan.
#
# Uso:  GODOT=/ruta/godot tools/run_tests.sh [res://tests/golden]
set -u
DIR="${1:-res://tests}"
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/project"

"$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1
LOG="$(mktemp)"
"$GODOT" --headless --path "$PROJECT" -s addons/gut/gut_cmdln.gd "-gdir=$DIR" -ginclude_subdirs -gexit >"$LOG" 2>&1
CODE=$?
cat "$LOG"
if grep -E 'SCRIPT ERROR|Parse Error|Ignoring script' "$LOG" >/dev/null; then
	echo "ERROR: hay scripts con errores o ignorados por GUT" >&2
	rm -f "$LOG"
	exit 1
fi
rm -f "$LOG"
exit $CODE
