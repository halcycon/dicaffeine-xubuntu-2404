#!/usr/bin/env bash
set -euo pipefail

# Refresh an existing Wyse box from this kit without reinstalling .debs or
# rewriting Dicaffeine player settings.
#
# Usage (on the Wyse, from the kit checkout):
#   cd ~/wyse-ndi-kit
#   ./scripts/update-wyse-ndi.sh
#
# Options (environment):
#   INSTALL_VBAN=auto|0|1   auto = update VBAN if already installed (default)
#   FORCE_VBAN_BUILD=1      rebuild vban_receptor during VBAN update
#   RESTART_DICAFFEINE=1    restart dicaffeine user service after merge

exec "$(dirname "$0")/../install-wyse-ndi.sh" --update "$@"
