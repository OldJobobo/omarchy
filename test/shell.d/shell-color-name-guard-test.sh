#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

# Qt 6.12 exports a QtQuick Color singleton. In any file with a bare
# `import QtQuick` it hides the qs.Commons singleton of the same name, whatever
# the import order, so every themed color reads as undefined. The shell's
# palette is ShellColor, and Color is left to mean only Qt's singleton.

uses=$(cd "$ROOT" && grep -rn '\<Color\.' --include=*.qml --include=*.js shell test/shell.d/fixtures || true)
if [[ -n $uses ]]; then
  printf '%s\n' "$uses" >&2
  fail "shell QML uses ShellColor, not the Color name Qt 6.12 shadows"
fi
pass "shell QML uses ShellColor, not the Color name Qt 6.12 shadows"

qmldir="$ROOT/shell/Commons/qmldir"
grep -qxF "singleton ShellColor 1.0 ShellColor.qml" "$qmldir" ||
  fail "qs.Commons registers the ShellColor singleton"
pass "qs.Commons registers the ShellColor singleton"

if grep -qE '^singleton Color ' "$qmldir"; then
  fail "qs.Commons does not register a Color singleton"
fi
pass "qs.Commons does not register a Color singleton"
