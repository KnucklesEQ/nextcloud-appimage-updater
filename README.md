# Nextcloud AppImage Updater
A lightweight Bash script to automate the updating process of the Nextcloud Desktop Client (.AppImage) on Linux systems.

It checks the GitHub API for the latest release, downloads it safely, verifies integrity, updates the symlink, and cleans up old versions while keeping the immediate previous version as a backup.

## Prerequisites

The script requires the following standard tools:
- `bash`
- `curl`
- `jq` (used to parse GitHub JSON)

On Debian/Ubuntu, you can install them with:
```bash
sudo apt update && sudo apt install curl jq
```

## License
Distributed under the MIT License. See LICENSE for more information.
