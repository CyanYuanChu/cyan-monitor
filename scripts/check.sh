#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
"build/Cyan Monitor.app/Contents/MacOS/Cyan Monitor" --self-test
codesign --verify --deep --strict "build/Cyan Monitor.app"
