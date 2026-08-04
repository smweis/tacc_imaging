#!/bin/bash
#SBATCH -J dcm2bids
#SBATCH -o logs/dcm2bids_%x_%j.out
#SBATCH -e logs/dcm2bids_%x_%j.err
#SBATCH -p development
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -t 00:20:00
#SBATCH --mail-type=FAIL
#SBATCH -A ACCOUNT_CODE
#SBATCH --mail-user=YOUR_EMAIL@domain.com

# Submit via the launcher (recommended: works from any directory, tags job
# name/log files with subject/session):
#   code/submit_dcm2bids.sh <SUBJECT_ID> <SESSION_ID> <ZIP_FILE> <--copy-template | --use-existing-config> [--validate] [--re-run] [--dry-run]
#
# Or submit directly (must run from the BIDS root; log filenames won't be
# tagged with subject/session):
#   sbatch code/run_dcm2bids.sh <SUBJECT_ID> <SESSION_ID> <ZIP_FILE> <--copy-template | --use-existing-config> [--validate] [--re-run] [--dry-run]

set -euo pipefail

# Slurm runs a spooled copy of this script, so it can't self-locate via
# BASH_SOURCE. submit_dcm2bids.sh exports SUBMIT_BIDS_DIR; direct sbatch
# submission falls back to SLURM_SUBMIT_DIR (the submission directory).
BIDS_DIR="${SUBMIT_BIDS_DIR:-$SLURM_SUBMIT_DIR}"
SCRIPT_DIR="$BIDS_DIR/code"
PROJECT_DIR="$(dirname "$BIDS_DIR")"

if [ ! -f "$BIDS_DIR/dataset_description.json" ] || [ ! -d "$BIDS_DIR/sourcedata" ]; then
    echo "ERROR: BIDS directory structure looks wrong (missing dataset_description.json or sourcedata/) at: $BIDS_DIR"
    exit 1
fi

module reset
source "$PROJECT_DIR/venvs/dcm2bids/bin/activate"

usage() {
    cat <<EOF
Usage (recommended, works from any directory, tags job name/log files with subject/session):
  code/submit_dcm2bids.sh <SUBJECT_ID> <SESSION_ID> <ZIP_FILE> <--copy-template | --use-existing-config> [--validate] [--re-run] [--dry-run]

Usage (direct submit, run from the BIDS root; log filenames not tagged with subject/session):
  sbatch code/$0 <SUBJECT_ID> <SESSION_ID> <ZIP_FILE> <--copy-template | --use-existing-config> [--validate] [--re-run] [--dry-run]

Required:
  SUBJECT_ID              Subject ID WITHOUT the 'sub-' prefix
  SESSION_ID              Session ID WITHOUT the 'ses-' prefix; must be 01 or 02
  ZIP_FILE                Zip filename in sourcedata/ (e.g. 1501_ses02.zip)
  --copy-template         Copy the session template to the subject/session config, overwriting any existing
  --use-existing-config   Require subject/session config to already exist; do not copy template

Optional:
  --validate              Run bids-validator-deno after conversion
  --re-run                Remove existing subject/session BIDS output before running
  --dry-run               Print resolved paths and commands that would run, then exit

Examples:
  code/submit_dcm2bids.sh 1501 01 1501_ses01.zip --copy-template
  code/submit_dcm2bids.sh 1501 02 1501_ses02.zip --use-existing-config --validate
  code/submit_dcm2bids.sh 1501 01 1501_ses01.zip --copy-template --dry-run

Important:
  SUBJECT_ID should NOT include 'sub-'.
  SESSION_ID should NOT include 'ses-'.
  ZIP_FILE must exist in sourcedata/.
  Direct submit (sbatch, not the launcher) must run from the BIDS root
  directory.
EOF
}

if [ "$#" -lt 4 ] || [ "$#" -gt 7 ]; then
    usage
    exit 1
fi

RAW_SUBID="$1"
SESSION_ID="$2"
ZIP_FILE="$3"

if [[ "$RAW_SUBID" == sub-* ]]; then
    echo "ERROR: SUBJECT_ID should NOT include 'sub-'. You entered: $RAW_SUBID"
    exit 1
fi

if [[ "$SESSION_ID" == ses-* ]]; then
    echo "ERROR: SESSION_ID should NOT include 'ses-'. Use: 01  not  ses-01"
    exit 1
fi

if [[ "$SESSION_ID" != "01" && "$SESSION_ID" != "02" ]]; then
    echo "ERROR: SESSION_ID must be exactly 01 or 02. You entered: $SESSION_ID"
    exit 1
fi

SUBID="sub-$RAW_SUBID"
SESID="ses-$SESSION_ID"

VALIDATE=false
RERUN=false
DRYRUN=false
CONFIG_MODE=""

shift 3
for arg in "$@"; do
    case "$arg" in
        --validate)         VALIDATE=true ;;
        --re-run)           RERUN=true ;;
        --dry-run)          DRYRUN=true ;;
        --copy-template)
            if [ -n "$CONFIG_MODE" ]; then
                echo "ERROR: Choose only one of --copy-template or --use-existing-config"
                exit 1
            fi
            CONFIG_MODE="copy-template"
            ;;
        --use-existing-config)
            if [ -n "$CONFIG_MODE" ]; then
                echo "ERROR: Choose only one of --copy-template or --use-existing-config"
                exit 1
            fi
            CONFIG_MODE="use-existing-config"
            ;;
        *)
            echo "ERROR: unknown option: $arg"
            usage
            exit 1
            ;;
    esac
done

if [ -z "$CONFIG_MODE" ]; then
    echo "ERROR: You must specify exactly one of --copy-template or --use-existing-config"
    usage
    exit 1
fi

CONFIG_DIR="$BIDS_DIR/code/configs"
ZIP_PATH="$BIDS_DIR/sourcedata/$ZIP_FILE"
SCRATCH_SRC="$SCRATCH/dcm2bids_src_${SUBID}_${SESID}"
TMP_ROOT="$SCRATCH/dcm2bids_work"
SUB_TMP_DIR="$TMP_ROOT/${SUBID}_${SESID}"
TEMPLATE_JSON="$CONFIG_DIR/dcm2bids_config_ses-${SESSION_ID}_template.json"
CONFIG_JSON="$CONFIG_DIR/dcm2bids_config_sub-${RAW_SUBID}_ses-${SESSION_ID}.json"
SUB_OUT_DIR="$BIDS_DIR/$SUBID/$SESID"
TMP_DCM2BIDS_DIR="$BIDS_DIR/tmp_dcm2bids/$SUBID/$SESID"

echo "=============================="
echo "BIDS DIR:     $BIDS_DIR"
echo "SUBID:        $SUBID"
echo "SESID:        $SESID"
echo "ZIP:          $ZIP_PATH"
echo "SCRATCH SRC:  $SCRATCH_SRC"
echo "CONFIG MODE:  $CONFIG_MODE"
echo "CONFIG:       $CONFIG_JSON"
echo "TEMPLATE:     $TEMPLATE_JSON"
echo "VALIDATE:     $VALIDATE"
echo "RE-RUN:       $RERUN"
echo "DRY-RUN:      $DRYRUN"
echo "=============================="

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

if [ "$DRYRUN" = true ]; then
    echo ""
    echo "DRY-RUN: would execute:"
    [ "$RERUN" = true ] && echo "  rm -rf $SUB_OUT_DIR"
    [ "$RERUN" = true ] && echo "  rm -rf $TMP_DCM2BIDS_DIR"
    echo "  unzip -o $ZIP_PATH -d $SCRATCH_SRC"
    echo "  dcm2bids -d $SCRATCH_SRC -p $RAW_SUBID -s $SESSION_ID -c $CONFIG_JSON -o $BIDS_DIR"
    [ "$VALIDATE" = true ] && echo "  bids-validator-deno $BIDS_DIR"
    echo "  rm -rf $SCRATCH_SRC"
    echo ""
    echo "No files were created or modified."
    exit 0
fi

case "$CONFIG_MODE" in
    copy-template)
        if [ ! -f "$TEMPLATE_JSON" ]; then
            echo "ERROR: template config not found: $TEMPLATE_JSON"
            exit 1
        fi
        cp "$TEMPLATE_JSON" "$CONFIG_JSON"
        echo "Copied template to subject/session config (clobbering any existing):"
        echo "  $CONFIG_JSON"
        ;;
    use-existing-config)
        if [ ! -f "$CONFIG_JSON" ]; then
            echo "ERROR: subject/session config not found: $CONFIG_JSON"
            echo "You chose --use-existing-config, so no template was copied."
            exit 1
        fi
        ;;
esac

if [ "$RERUN" = true ]; then
    echo "Removing existing BIDS output for $SUBID $SESID"
    rm -rf "$SUB_OUT_DIR"
    echo "Removing existing tmp_dcm2bids directory for $SUBID $SESID"
    rm -rf "$TMP_DCM2BIDS_DIR"
fi

echo "Extracting DICOMs to scratch: $SCRATCH_SRC"
rm -rf "$SCRATCH_SRC"
mkdir -p "$SCRATCH_SRC"
unzip -o "$ZIP_PATH" -d "$SCRATCH_SRC"

rm -rf "$SUB_TMP_DIR"
mkdir -p "$SUB_TMP_DIR"

DCM2BIDS_CMD=(
    dcm2bids
    -d "$SCRATCH_SRC"
    -p "$RAW_SUBID"
    -s "$SESSION_ID"
    -c "$CONFIG_JSON"
    -o "$BIDS_DIR"
)

echo "Running: ${DCM2BIDS_CMD[*]}"
"${DCM2BIDS_CMD[@]}"

rm -rf "$SUB_TMP_DIR"
rm -rf "$SCRATCH_SRC"
echo "Cleaned up scratch DICOM extraction."

if [ "$VALIDATE" = true ]; then
    echo "Running BIDS validator on $BIDS_DIR"
    bids-validator-deno "$BIDS_DIR"
fi

echo "Done: $SUBID $SESID"
