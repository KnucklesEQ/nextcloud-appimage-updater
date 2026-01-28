#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
CONFIG_FILE="${SCRIPT_DIR}/nextcloud-updater.conf"
APP_NAME="Nextcloud_Files"
SYMLINK_NAME="Nextcloud.AppImage"
BASE_DIR=""
APP_DIR=""
RELEASES_DIR=""
SYMLINK=""
tmp_path=""
API_URL="https://api.github.com/repos/nextcloud-releases/desktop/releases/latest"

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

for cmd in curl jq uname readlink; do
  command -v "$cmd" >/dev/null 2>&1 || die "Missing dependency: $cmd"
done

write_config() {
  printf 'BASE_DIR="%s"\n' "$BASE_DIR" >"$CONFIG_FILE" || die "Unable to write config: $CONFIG_FILE"
}

read_config() {
  [[ -f "$CONFIG_FILE" ]] || return 1
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  if [[ -z "${BASE_DIR:-}" ]]; then
    die "Invalid config: BASE_DIR is not set in $CONFIG_FILE"
  fi
  if [[ ! -d "$BASE_DIR" ]]; then
    die "Configured directory not found: $BASE_DIR"
  fi
  return 0
}

prompt_for_base_dir() {
  local input=""
  while true; do
    printf 'Apps base directory [%s]: ' "$BASE_DIR"
    read -r input
    if [[ -z "$input" ]]; then
      input="$BASE_DIR"
    fi
    if [[ -d "$input" ]]; then
      BASE_DIR="$input"
      break
    fi
    log "Invalid path. Enter an existing directory, for example: /home/user/Applications."
  done
}

confirm_prompt() {
  local message="$1"
  local answer=""
  local answer_lower=""
  printf '%s [Y/n]: ' "$message"
  read -r answer
  if [[ -z "$answer" ]]; then
    return 0
  fi
  answer_lower="${answer,,}"
  case "$answer_lower" in
    s|si|y|yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_directories() {
  if [[ ! -d "$APP_DIR" ]]; then
    mkdir -p -- "$APP_DIR" || die "Unable to create directory: $APP_DIR"
  fi
  if [[ ! -d "$RELEASES_DIR" ]]; then
    mkdir -p -- "$RELEASES_DIR" || die "Unable to create directory: $RELEASES_DIR"
  fi
}

relocate_script() {
  local target_script="${APP_DIR}/${SCRIPT_NAME}"
  local target_config="${APP_DIR}/nextcloud-updater.conf"
  if [[ "$SCRIPT_DIR" == "$APP_DIR" ]]; then
    return 0
  fi
  if ! confirm_prompt "Move script and config to $APP_DIR?"; then
    return 0
  fi
  cp -f -- "$SCRIPT_PATH" "$target_script" || die "Unable to copy script to: $target_script"
  if [[ -f "$CONFIG_FILE" && "$CONFIG_FILE" != "$target_config" ]]; then
    cp -f -- "$CONFIG_FILE" "$target_config" || die "Unable to copy config to: $target_config"
  fi
  rm -f -- "$SCRIPT_PATH" || die "Unable to remove original script: $SCRIPT_PATH"
  if [[ -f "$CONFIG_FILE" && "$CONFIG_FILE" != "$target_config" ]]; then
    rm -f -- "$CONFIG_FILE" || die "Unable to remove original config: $CONFIG_FILE"
  fi
  log "Script moved to: $target_script"
}

if ! read_config; then
  if [[ "$(basename "$SCRIPT_DIR")" == "$APP_NAME" ]]; then
    BASE_DIR="$(dirname "$SCRIPT_DIR")"
  else
    BASE_DIR="$SCRIPT_DIR"
  fi
  prompt_for_base_dir
  APP_DIR="${BASE_DIR}/${APP_NAME}"
  RELEASES_DIR="${APP_DIR}/releases"
  ensure_directories
  write_config
else
  APP_DIR="${BASE_DIR}/${APP_NAME}"
  RELEASES_DIR="${APP_DIR}/releases"
  ensure_directories
fi

SYMLINK="${APP_DIR}/${SYMLINK_NAME}"

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)
    arch="x86_64"
    ;;
  aarch64|arm64)
    arch="arm64"
    ;;
  *)
    die "Unsupported architecture: $arch"
    ;;
esac

release_json="$(curl -fsSL "$API_URL")"
tag_name="$(jq -r '.tag_name // empty' <<<"$release_json")"
[[ -n "$tag_name" ]] || die "Unable to read tag_name from GitHub API"

asset_name="$(jq -r --arg arch "$arch" '
  [ .assets[] | select(.name | endswith(".AppImage")) | select(.name | contains($arch)) ][0].name //
  [ .assets[] | select(.name | endswith(".AppImage")) ][0].name // empty
' <<<"$release_json")"

asset_url="$(jq -r --arg arch "$arch" '
  [ .assets[] | select(.name | endswith(".AppImage")) | select(.name | contains($arch)) ][0].browser_download_url //
  [ .assets[] | select(.name | endswith(".AppImage")) ][0].browser_download_url // empty
' <<<"$release_json")"

[[ -n "$asset_name" && -n "$asset_url" ]] || die "No AppImage asset found in latest release"

tag_version="${tag_name#v}"

current_target=""
current_version=""
if [[ -L "$SYMLINK" ]]; then
  current_target="$(readlink -f "$SYMLINK" || true)"
  current_name="$(basename "$current_target")"
  if [[ "$current_name" =~ ^Nextcloud-(.+)-${arch}\.AppImage$ ]]; then
    current_version="${BASH_REMATCH[1]}"
  fi
fi

if [[ -n "$current_version" && "$current_version" == "$tag_version" ]]; then
  log "Already up to date: $tag_version"
  exit 0
fi

download_path="${RELEASES_DIR}/${asset_name}"
tmp_path="${download_path}.part"

cleanup() {
  [[ -f "$tmp_path" ]] && rm -f -- "$tmp_path"
}
trap cleanup EXIT

if [[ -f "$download_path" ]]; then
  log "AppImage already present: $download_path"
else
  log "Downloading $asset_name"
  curl -fL --retry 3 --retry-delay 2 -o "$tmp_path" "$asset_url"
  mv -f -- "$tmp_path" "$download_path"
fi

chmod +x -- "$download_path"

log "Updating symlink: $SYMLINK -> $download_path"
ln -sfn -- "$download_path" "$SYMLINK"

keep_new="$download_path"
keep_prev=""
if [[ -n "$current_target" && -f "$current_target" ]]; then
  keep_prev="$current_target"
fi

removed_any=0
for f in "${RELEASES_DIR}"/Nextcloud-*.AppImage; do
  [[ -e "$f" ]] || continue
  if [[ "$f" == "$keep_new" ]]; then
    continue
  fi
  if [[ -n "$keep_prev" && "$f" == "$keep_prev" ]]; then
    log "Keeping backup version: $f"
    continue
  fi
  rm -f -- "$f"
  removed_any=1
  log "Removed old version: $f"
done

log "Installed version: $tag_version"
log "Symlink target: $(readlink -f "$SYMLINK")"
if [[ "$removed_any" -eq 0 ]]; then
  log "No old versions removed"
fi

relocate_script
