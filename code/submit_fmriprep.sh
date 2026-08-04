#!/bin/bash
# Launcher for run_fmriprep_subject_session.sbatch. Can be run from any
# directory: BIDS_DIR is resolved from this script's own location, and
# logs always land in BIDS_DIR/logs/, tagged with subject/session.
#
# Usage:
#   code/submit_fmriprep.sh <SUBJECT_ID> <SESSION_ID> [--dry-run]

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib_submit.sh"

if [ "$#" -lt 2 ]; then
    echo "Usage: code/submit_fmriprep.sh <SUBJECT_ID> <SESSION_ID> [--dry-run]"
    exit 1
fi

submit_job fmriprep run_fmriprep_subject_session.sbatch "$@"
