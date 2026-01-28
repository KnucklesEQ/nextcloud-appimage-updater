# Nextcloud AppImage Updater
A lightweight Bash script to automate updates for the Nextcloud Desktop AppImage (and
other GitHub-hosted AppImage releases) on Linux.

It checks the GitHub API for the latest release, downloads the AppImage, updates a
symlink, and keeps the immediate previous version as a backup.

## Prerequisites

The script requires the following tools:
- `bash`
- `curl`
- `jq`
- `uname`
- `readlink`

Network access to `https://api.github.com` is required.

On Debian/Ubuntu, you can install dependencies with:
```bash
sudo apt update && sudo apt install curl jq
```

## Quick start

Run the script directly:
```bash
bash update-nextcloud.sh
```

On first run, the script will prompt for:
- The base directory that stores app folders.
- The GitHub repository (owner/repo) or a GitHub AppImage download URL.

It will create the configuration file automatically and can optionally move the
script and config into the app folder at the end of the run. The symlink is meant
as a stable target for desktop launchers or system shortcuts.

## Configuration

Config file location:
- `${BASE_DIR}/Nextcloud_Files/nextcloud-updater.conf`

Supported settings:
- `BASE_DIR` - Root directory that contains the `Nextcloud_Files` folder.
- `REPO_SLUG` - GitHub repository in `owner/repo` form.

You can provide the repository as either:
- `owner/repo`, or
- A GitHub download URL like:
  `https://github.com/owner/repo/releases/download/tag/file.AppImage`

The script normalizes URLs to `owner/repo` before saving.

Example configuration:
```ini
BASE_DIR="/home/user/Applications"
REPO_SLUG="nextcloud-releases/desktop"
```

## Directory layout

After first run, the layout looks like:
```text
Base Dir/
└── Nextcloud_Files/
    ├── update-nextcloud.sh
    ├── nextcloud-updater.conf
    ├── Nextcloud.AppImage -> releases/Nextcloud-vX.Y.Z.AppImage
    └── releases/
        ├── Nextcloud-vX.Y.Z.AppImage (current)
        └── Nextcloud-vX.Y.Y.AppImage (previous backup)
```

## Usage

Update to the latest release:
```bash
bash update-nextcloud.sh
```

Show help:
```bash
bash update-nextcloud.sh --help
```

## Behavior

- Detects architecture via `uname -m` and selects a matching AppImage asset.
- Downloads the latest release asset to `releases/`.
- Updates the `Nextcloud.AppImage` symlink to the new release.
- Keeps the previous AppImage as a backup and removes other AppImages.

## Security

- Downloads are fetched over HTTPS from GitHub releases.
- The script does not verify cryptographic signatures or checksums.
- Only use repositories and releases you trust.

## Troubleshooting

- **Missing dependency**: Install the required tools listed above.
- **Invalid config**: Edit `nextcloud-updater.conf` and ensure `BASE_DIR` and
  `REPO_SLUG` are valid.
- **No AppImage asset found**: Confirm the repository has AppImage assets in
  the latest release.
- **Permission errors**: Ensure the base directory is writable.

## License

Distributed under the MIT License. See `LICENSE` for more information.
