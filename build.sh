#!/usr/bin/env bash
# Linux counterpart of build.ps1: debug/release select the signing profile.
# Both distributable types retain the project's release-mode Flutter compilation.
set -euo pipefail
BUILD_TYPE="${1:-hap}"
PROFILE="${2:-$([[ "$BUILD_TYPE" == hap ]] && echo debug || echo release)}"
[[ "$BUILD_TYPE" == hap || "$BUILD_TYPE" == app ]] || { echo 'Usage: ./build.sh hap|app debug|release [--offline]'; exit 2; }
[[ "$PROFILE" == debug || "$PROFILE" == release ]] || exit 2
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/flutter_327}"
export DEVECO_ROOT="${DEVECO_ROOT:-$HOME/command-line-tools-26.0.0.821}"
export DEVECO_SDK_HOME="$DEVECO_ROOT/sdk"
export HOS_SDK_HOME="$DEVECO_SDK_HOME"
export DEVECO_NODE_HOME="$DEVECO_ROOT/tool/node"
export NODE_HOME="$DEVECO_NODE_HOME"
export JAVA_HOME="${JAVA_HOME:-$HOME/jdk-21}"
export PUB_CACHE="$PROJECT_ROOT/.dart_tool/pub-cache"
export GIT_LFS_SKIP_SMUDGE=1
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PATH="$FLUTTER_ROOT/bin:$DEVECO_ROOT/bin:$DEVECO_NODE_HOME/bin:$JAVA_HOME/bin:$PATH"
cd "$PROJECT_ROOT"
python3 tool/prepare_linux_build.py profile "$PROFILE"
flutter --version
pub_args=(pub get)
[[ "${3:-}" != --offline ]] || pub_args+=(--offline)
flutter "${pub_args[@]}"
python3 tool/prepare_linux_build.py plugins
python3 tool/prepare_linux_build.py mpv
started="$(date +%s)"
flutter build "$BUILD_TYPE" --release --no-pub
python3 tool/prepare_linux_build.py verify "$BUILD_TYPE" "$PROFILE" "$started"
