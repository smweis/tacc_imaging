#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIDS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$BIDS_DIR")"

usage() {
    cat <<EOF
Usage:
  bash $0 <SUBJECT_ID> <SESSION_ID> <ZIP_FILE>

Required:
  SUBJECT_ID    Subject ID WITHOUT the 'sub-' prefix (e.g. 1603)
  SESSION_ID    Session ID WITHOUT the 'ses-' prefix (e.g. 01 or 02)
  ZIP_FILE      Zip filename in sourcedata/ (e.g. 1603_ses02.zip)

Examples:
  bash $0 1603 02 1603_ses02.zip
  bash $0 utadev01 01 utadev01_ses01.zip

Purpose:
  Extracts DICOMs from the zip to \$SCRATCH, runs dcm2bids_helper, and
  writes converted NIfTI JSON sidecars for inspection. Use this to:

    - Build a new dcm2bids config for a session type you haven't seen before
    - Debug unexpected 'No Pairing' outputs from run_dcm2bids.sh
    - Confirm which DICOM fields are available for config matching

  After it runs, inspect the JSON sidecars in the output directory printed
  below. Each .json file corresponds to one DICOM series.

  Key fields to look for:
    SeriesDescription           Most reliable identifier for a scan type
    ProtocolName                Often matches SeriesDescription
    NonlinearGradientCorrection Use to distinguish T1_MPRAGE from T1_MPRAGE_ND
    ImageTypeText               Use to select among duplicate-looking reconstructions

  Do NOT rely on series number prefixes (e.g. 005_, 006_) — these vary
  across participants and sessions.

  All output is written to \$SCRATCH and will be auto-cleaned by TACC.
  Nothing is written to the BIDS directory.
EOF
}

if [[ $# -ne 3 ]]; then
    usage
    exit 1
fi

RAW_SUBID="$1"
SESSION_ID="$2"
ZIP_FILE="$3"

if [[ "$RAW_SUBID" == sub-* ]]; then
    echo "ERROR: SUBJECT_ID should NOT include 'sub-'."
    exit 1
fi

if [[ "$SESSION_ID" == ses-* ]]; then
    echo "ERROR: SESSION_ID should NOT include 'ses-'."
    exit 1
fi

ZIP_PATH="$BIDS_DIR/sourcedata/$ZIP_FILE"
HELPER_SCRATCH="$SCRATCH/dcm2bids_helper_sub-${RAW_SUBID}_ses-${SESSION_ID}"
DICOM_DIR="$HELPER_SCRATCH/dicoms"

if [[ ! -f "$ZIP_PATH" ]]; then
    echo "ERROR: zip file not found: $ZIP_PATH"
    exit 1
fi

if [[ ! -r "$ZIP_PATH" ]]; then
    echo "Zip file not readable, attempting to fix permissions: $ZIP_PATH"
    chmod g+r "$ZIP_PATH" 2>/dev/null || true
fi

if [[ ! -r "$ZIP_PATH" ]]; then
    echo "ERROR: no read permission on zip file: $ZIP_PATH"
    echo "Ask the file owner to run: chmod g+r $ZIP_PATH"
    exit 1
fi

module reset
source "$PROJECT_DIR/venvs/dcm2bids/bin/activate"

echo "Running dcm2bids_helper"
echo "  Subject: sub-$RAW_SUBID"
echo "  Session: ses-$SESSION_ID"
echo "  Zip:     $ZIP_PATH"
echo "  Output:  $HELPER_SCRATCH/tmp_dcm2bids/helper/"
echo

echo "Extracting DICOMs to scratch..."
rm -rf "$HELPER_SCRATCH"
mkdir -p "$DICOM_DIR"
unzip -o "$ZIP_PATH" -d "$DICOM_DIR"

dcm2bids_helper \
  -d "$DICOM_DIR" \
  -o "$HELPER_SCRATCH" \
  --force

echo
echo "Done. Inspect JSON sidecars here:"
echo "  $HELPER_SCRATCH/tmp_dcm2bids/helper/"
echo
echo "Each .json file is one DICOM series. Look for SeriesDescription,"
echo "ProtocolName, NonlinearGradientCorrection, and ImageTypeText to"
echo "build or debug your dcm2bids config."
