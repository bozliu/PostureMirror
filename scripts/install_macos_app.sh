#!/usr/bin/env bash
set -euo pipefail

SOURCE_APP=""
APPS_DIR="/Applications"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/install_macos_app.sh --source-app <path/to/PostureMirror.app> [--apps-dir /Applications] [--dry-run]

Options:
  --source-app   Required source app bundle path (for example from mounted DMG)
  --apps-dir     Applications directory (default: /Applications)
  --dry-run      Print actions without modifying filesystem
EOF
}

log() {
  printf '[install] %s\n' "$1"
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: $*"
    return 0
  fi
  "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-app)
      SOURCE_APP="${2:-}"
      shift 2
      ;;
    --apps-dir)
      APPS_DIR="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$SOURCE_APP" ]]; then
  echo "--source-app is required" >&2
  usage >&2
  exit 2
fi

SOURCE_APP="$(cd "$(dirname "$SOURCE_APP")" && pwd)/$(basename "$SOURCE_APP")"
if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Source app not found: $SOURCE_APP" >&2
  exit 1
fi

SOURCE_EXEC="$SOURCE_APP/Contents/MacOS/PostureMirror"
if [[ ! -f "$SOURCE_EXEC" ]]; then
  echo "Invalid app bundle (missing executable): $SOURCE_EXEC" >&2
  exit 1
fi

TARGET_APP="$APPS_DIR/PostureMirror.app"
TMP_BASE="/private/tmp"
if [[ ! -d "$TMP_BASE" || ! -w "$TMP_BASE" ]]; then
  TMP_BASE="${TMPDIR:-/tmp}"
fi
if [[ ! -d "$TMP_BASE" || ! -w "$TMP_BASE" ]]; then
  echo "No writable temp directory found. Checked /private/tmp and ${TMPDIR:-/tmp}" >&2
  exit 1
fi
TMP_DIR="$(mktemp -d "${TMP_BASE%/}/posturemirror-install.XXXXXX")"
TMP_APP="$TMP_DIR/PostureMirror.app"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ "$DRY_RUN" -eq 0 && ! -d "$APPS_DIR" ]]; then
  echo "Applications directory does not exist: $APPS_DIR" >&2
  exit 1
fi

if [[ "$DRY_RUN" -eq 0 && ! -w "$APPS_DIR" ]]; then
  echo "No write permission to $APPS_DIR. Re-run with sudo if needed." >&2
  exit 1
fi

log "Validating source app in temporary workspace"
run ditto "$SOURCE_APP" "$TMP_APP"

TMP_EXEC="$TMP_APP/Contents/MacOS/PostureMirror"
if [[ ! -f "$TMP_EXEC" ]]; then
  echo "Copied app invalid (missing executable): $TMP_EXEC" >&2
  exit 1
fi

if [[ -d "$TARGET_APP" ]]; then
  log "Removing existing app: $TARGET_APP"
  run rm -rf "$TARGET_APP"
fi

log "Installing app to: $TARGET_APP"
run ditto "$TMP_APP" "$TARGET_APP"

if command -v xattr >/dev/null 2>&1; then
  log "Clearing quarantine attribute"
  run xattr -dr com.apple.quarantine "$TARGET_APP" || true
else
  log "xattr not available, skipping quarantine cleanup"
fi

log "Install complete. No .bak folders were created."
