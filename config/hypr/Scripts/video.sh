#!/usr/bin/env bash

## Check Native Binaries (Priority order: mpv -> vlc -> celluloid)
if command -v mpv &>/dev/null; then
    CMD=(mpv --player-operation-mode=pseudo-gui)
elif command -v vlc &>/dev/null; then
    CMD=(vlc)
elif command -v celluloid &>/dev/null; then
    CMD=(celluloid)

## Check Flatpaks (Priority order: mpv -> vlc -> celluloid)
elif command -v flatpak &>/dev/null && flatpak info io.mpv.Mpv &>/dev/null; then
    CMD=(flatpak run io.mpv.Mpv)
elif command -v flatpak &>/dev/null && flatpak info org.videolan.VLC &>/dev/null; then
    CMD=(flatpak run org.videolan.VLC)
elif command -v flatpak &>/dev/null && flatpak info io.github.celluloid_player.Celluloid &>/dev/null; then
    CMD=(flatpak run io.github.celluloid_player.Celluloid)

## Fallback if no player is found
else
    echo "Error: No compatible video player found (mpv, vlc, celluloid)." >&2
    exit 1
fi

"${CMD[@]}" "$@"
