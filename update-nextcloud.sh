#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME}/Aplicaciones"
SYMLINK="${BASE_DIR}/Nextcloud_Files"
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

[[ -d "$BASE_DIR" ]] || die "Base directory not found: $BASE_DIR"

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

download_path="${BASE_DIR}/${asset_name}"
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
for f in "${BASE_DIR}"/Nextcloud-*.AppImage; do
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
