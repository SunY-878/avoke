#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ ! -d "$TASK_ROOT/dist/Sky Island.app" ]; then
    "$TASK_ROOT/Scripts/build.sh"
fi
open "$TASK_ROOT/dist/Sky Island.app"
