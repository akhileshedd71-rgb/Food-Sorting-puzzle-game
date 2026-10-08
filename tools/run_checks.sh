#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${GODOT_BIN:-}" ]]; then
  if [[ -x /workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64 ]]; then
    GODOT_BIN=/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64
  elif [[ -x "$project_dir/../garden-table-tools/godot/Godot_v4.7.2-stable_linux.x86_64" ]]; then
    GODOT_BIN="$project_dir/../garden-table-tools/godot/Godot_v4.7.2-stable_linux.x86_64"
  elif command -v godot >/dev/null; then GODOT_BIN="$(command -v godot)"
  elif command -v godot4 >/dev/null; then GODOT_BIN="$(command -v godot4)"
  else
    echo 'Set GODOT_BIN to Godot 4.7.2, or run tools/setup_environment.sh and source its environment.sh.' >&2
    exit 1
  fi
fi
engine_version="$("$GODOT_BIN" --headless --version)"
if [[ "$engine_version" != 4.7.2.* ]]; then
  printf 'Expected Godot 4.7.2, got %s. Set GODOT_BIN to the pinned engine.\n' "$engine_version" >&2
  exit 1
fi
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/garden-table-checks.XXXXXX")"
trap 'rm -rf -- "$check_dir"' EXIT
# Isolate saved progress from interactive play while running tests.
export GARDEN_UI_TEST=1
export GARDEN_TEST_SAVE_DIR="$check_dir/save-tests"
export XDG_DATA_HOME="$check_dir/data"
export XDG_CONFIG_HOME="$check_dir/config"
export XDG_CACHE_HOME="$check_dir/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
run_godot() {
  local log="$check_dir/godot.log"
  "$GODOT_BIN" --headless --path "$project_dir" "$@" 2>&1 | tee "$log"
  if rg -q '(^|[[:space:]])(SCRIPT ERROR|Parse Error|ERROR:)' "$log"; then
    echo 'Godot reported errors; check failed.' >&2
    exit 1
  fi
}
run_godot --editor --import --quit
test_count=0
for test_script in "$project_dir"/tests/*_tests.gd; do
  [[ -f "$test_script" ]] || continue
  test_count=$((test_count + 1))
  printf '\nRunning %s\n' "${test_script##*/}"
  run_godot --script "$test_script"
done
if [[ "$test_count" -eq 0 ]]; then
  echo 'No tests/*_tests.gd scripts found; validation is incomplete.' >&2
  exit 1
fi
run_godot --quit-after 10
printf '\nGodot import, test scripts, and launch check passed.\n'
