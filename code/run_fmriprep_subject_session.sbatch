#!/bin/bash
#SBATCH -J fmriprep
#SBATCH -p development
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH -t 2:00:00
#SBATCH -o logs/fmriprep_%x_%j.out
#SBATCH -e logs/fmriprep_%x_%j.err
#SBATCH --mail-type=FAIL
#SBATCH -A ACCOUNT_CODE
#SBATCH --mail-user=YOUR_EMAIL@domain.com

# Submit via the launcher (recommended: works from any directory, tags job
# name/log files with subject/session):
#   code/submit_fmriprep.sh <SUBJECT_ID> <SESSION_ID> [--dry-run]
#
# Or submit directly (must run from the BIDS root):
#   sbatch code/run_fmriprep_subject_session.sbatch <SUBJECT_ID> <SESSION_ID> [--dry-run]
#
# SUBJECT_ID: WITHOUT "sub-"
# SESSION_ID: WITHOUT "ses-" (defaults to 01)

set -eo pipefail

# Slurm runs a spooled copy of this script, so it can't self-locate via
# BASH_SOURCE. submit_fmriprep.sh exports SUBMIT_BIDS_DIR; direct sbatch
# submission falls back to SLURM_SUBMIT_DIR (the submission directory).
BIDS_DIR="${SUBMIT_BIDS_DIR:-$SLURM_SUBMIT_DIR}"
SCRIPT_DIR="$BIDS_DIR/code"
PROJECT_DIR="$(dirname "$BIDS_DIR")"

module load tacc-apptainer

SUBJECT=${1:?ERROR: provide subject ID without sub- prefix, e.g. 1501}
SESSION=${2:-01}

DRYRUN=false
for arg in "${@:3}"; do
    case "$arg" in
        --dry-run) DRYRUN=true ;;
        *) echo "ERROR: unknown option: $arg"; exit 1 ;;
    esac
done

OUT_DIR="$BIDS_DIR/derivatives/fmriprep"
WORK_DIR="$SCRATCH/fmriprep_work/sub-${SUBJECT}_ses-${SESSION}"
SIF="$PROJECT_DIR/containers/fmriprep-25.2.5.sif"
FS_LICENSE="$PROJECT_DIR/license.txt"

mkdir -p "$BIDS_DIR/logs"
mkdir -p "$OUT_DIR"
mkdir -p "$WORK_DIR"

echo "Subject:    sub-${SUBJECT}"
echo "Session:    ses-${SESSION}"
echo "BIDS dir:   ${BIDS_DIR}"
echo "Output dir: ${OUT_DIR}"
echo "Work dir:   ${WORK_DIR}"
echo "Container:  ${SIF}"
echo "Dry-run:    ${DRYRUN}"

if [ "$DRYRUN" = true ]; then
    echo ""
    echo "DRY-RUN: would execute:"
    echo "  apptainer run --cleanenv \\"
    echo "    -B ${BIDS_DIR}:${BIDS_DIR} \\"
    echo "    -B ${PROJECT_DIR}:${PROJECT_DIR} \\"
    echo "    -B ${SCRATCH}:${SCRATCH} \\"
    echo "    ${SIF} \\"
    echo "    ${BIDS_DIR} ${OUT_DIR} participant \\"
    echo "    --participant-label ${SUBJECT} --session-label ${SESSION} \\"
    echo "    --fs-license-file ${FS_LICENSE} --work-dir ${WORK_DIR} \\"
    echo "    --nthreads ${SLURM_CPUS_PER_TASK} --omp-nthreads 4 --mem_mb 45000 \\"
    echo "    --output-spaces MNI152NLin2009cAsym:res-2 T1w --skip-bids-validation"
    echo ""
    echo "No files were created or modified."
    exit 0
fi

echo ""
echo "Starting fMRIPrep"
echo "Job ID: ${SLURM_JOB_ID}"
echo "Node: $(hostname)"

apptainer run --cleanenv \
  -B "${BIDS_DIR}":"${BIDS_DIR}" \
  -B "${PROJECT_DIR}":"${PROJECT_DIR}" \
  -B "${SCRATCH}":"${SCRATCH}" \
  "${SIF}" \
  "${BIDS_DIR}" \
  "${OUT_DIR}" \
  participant \
  --participant-label "${SUBJECT}" \
  --fs-license-file "${FS_LICENSE}" \
  --work-dir "${WORK_DIR}" \
  --nthreads "${SLURM_CPUS_PER_TASK}" \
  --omp-nthreads 4 \
  --mem_mb 45000 \
  --output-spaces MNI152NLin2009cAsym:res-2 T1w \
  --skip-bids-validation
