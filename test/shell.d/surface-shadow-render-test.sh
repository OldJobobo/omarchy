#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if ! python -c 'import PySide6.QtQuick' >/dev/null 2>&1; then
  skip "offscreen shadow rendering requires optional Python PySide6"
  exit 0
fi

# No live desktop or shell process: render a small Qt Quick scene offscreen.
QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=opengl QT_QUICK_BACKEND=rhi \
  python "$ROOT/test/shell.d/fixtures/surface-shadow-render.py"
