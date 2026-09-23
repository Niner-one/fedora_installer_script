#!/usr/bin/env bash

## Create directory if it doesn't exist
mkdir -p "$HOME/Pictures/Screenshots"

## Output filename with timestamp
OUTPUT_FILE="$HOME/Pictures/Screenshots/Screenshot-$(date '+%Y%m%d-%H%M%S').png"

## Determine whether to use native satty or flatpak
if command -v satty &>/dev/null; then
    SATTY_CMD=(satty)
else
    SATTY_CMD=(flatpak run org.satty.Satty)
fi

## Run grim/slurp pipeline
grim -g "$(slurp)" - | "${SATTY_CMD[@]}" --filename - --output-filename "$OUTPUT_FILE"
