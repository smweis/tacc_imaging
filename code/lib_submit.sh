#!/bin/bash
# Shared helper sourced by submit_*.sh launchers. Not meant to be run directly.
#
# Resolves BIDS_DIR from this file's own location (not from the caller's
# current directory), so a submit_*.sh script works no matter where it's
# invoked from. Provides submit_job(), which tags the Slurm job name and
# log filenames with subject/session and always writes logs to
# BIDS_DIR/logs/, then hands off to sbatch.
#
# Slurm copies submitted scripts to a spool file before running them
# (e.g. /var/spool/slurmd/job<id>/slurm_script), so the job body can't
# self-locate via BASH_SOURCE the way this file does. Instead, we export
# SUBMIT_BIDS_DIR here; sbatch propagates the submitting shell's
# environment into the job by default, so run_*.sh scripts can read it
# directly instead of guessing their own location.

set -euo pipefail

LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIDS_DIR="$(dirname "$LIB_SCRIPT_DIR")"
LOG_DIR="$BIDS_DIR/logs"

if [ ! -f "$BIDS_DIR/dataset_description.json" ] || [ ! -d "$BIDS_DIR/sourcedata" ]; then
    echo "ERROR: BIDS directory structure looks wrong (missing dataset_description.json or sourcedata/) at: $BIDS_DIR" >&2
    exit 1
fi

export SUBMIT_BIDS_DIR="$BIDS_DIR"

# submit_job <step> <target_script> <SUBJECT_ID> <SESSION_ID> [rest of args...]
submit_job() {
    local step="$1"
    local target_script="$2"
    shift 2

    if [ "$#" -lt 2 ]; then
        echo "ERROR: expected SUBJECT_ID and SESSION_ID as the first two arguments." >&2
        exit 1
    fi

    local raw_subid="$1"
    local session_id="$2"
    local jobname="${step}_${raw_subid}_${session_id}"

    mkdir -p "$LOG_DIR"

    echo "Submitting $step for subject $raw_subid, session $session_id"
    echo "  Script: $LIB_SCRIPT_DIR/$target_script"
    echo "  Logs:   $LOG_DIR/${jobname}_<jobid>.out / .err"

    sbatch -J "$jobname" \
        -o "$LOG_DIR/${jobname}_%j.out" \
        -e "$LOG_DIR/${jobname}_%j.err" \
        "$LIB_SCRIPT_DIR/$target_script" "$@"
}
