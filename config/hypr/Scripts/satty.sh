#!/usr/bin/env bash
set -o pipefail

## Create directory if it doesn't exist
mkdir -p "$HOME/Pictures/Screenshots" || exit 1

## Output filename with timestamp
OUTPUT_FILE="$HOME/Pictures/Screenshots/Screenshot-$(date '+%Y%m%d-%H%M%S').png"

## Determine whether to use native satty or flatpak
if command -v satty &>/dev/null; then
    SATTY_CMD=(satty)
elif command -v flatpak &>/dev/null; then
    SATTY_CMD=(flatpak run org.satty.Satty)
else
    echo "Neither Satty nor Flatpak is available." >&2
    exit 1
fi

## Run grim/slurp pipeline
GEOMETRY=$(slurp) || exit 0
[[ -n "$GEOMETRY" ]] || exit 0
grim -g "$GEOMETRY" - | "${SATTY_CMD[@]}" --filename - --output-filename "$OUTPUT_FILE"
