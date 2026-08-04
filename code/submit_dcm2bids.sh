#!/bin/bash
# Launcher for run_dcm2bids.sh. Can be run from any directory: BIDS_DIR is
# resolved from this script's own location, and logs always land in
# BIDS_DIR/logs/, tagged with subject/session.
#
# Usage:
#   code/submit_dcm2bids.sh <SUBJECT_ID> <SESSION_ID> <ZIP_FILE> <--copy-template | --use-existing-config> [--validate] [--re-run] [--dry-run]

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib_submit.sh"

if [ "$#" -lt 4 ]; then
    echo "Usage: code/submit_dcm2bids.sh <SUBJECT_ID> <SESSION_ID> <ZIP_FILE> <--copy-template | --use-existing-config> [--validate] [--re-run] [--dry-run]"
    exit 1
fi

RAW_SUBID="$1"
SESSION_ID="$2"
ZIP_FILE="$3"
ZIP_PATH="$BIDS_DIR/sourcedata/$ZIP_FILE"

if [ ! -f "$ZIP_PATH" ]; then
    echo "ERROR: zip file not found: $ZIP_PATH"
    exit 1
fi

if [ ! -r "$ZIP_PATH" ]; then
    echo "Zip file not readable, attempting to fix permissions: $ZIP_PATH"
    chmod g+r "$ZIP_PATH" 2>/dev/null || true
fi

if [ ! -r "$ZIP_PATH" ]; then
    echo "ERROR: no read permission on zip file: $ZIP_PATH"
    echo "Ask the file owner to run: chmod g+r $ZIP_PATH"
    exit 1
fi

submit_job dcm2bids run_dcm2bids.sh "$@"
