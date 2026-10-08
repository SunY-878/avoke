#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$TASK_ROOT/Scripts/build.sh"
open "$TASK_ROOT/dist/Sky Island.app" --args "$@"
