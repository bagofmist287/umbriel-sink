#!/usr/bin/env bash
# A slow Overview selection must not steal focus after the user chooses a peer
# during its outstanding desktop commit barrier.
set -euo pipefail
export OVERVIEW_COMMIT_SWITCH_TARGET=1
source "$(dirname "${BASH_SOURCE[0]}")/376_overview_sink_commit.sh"
