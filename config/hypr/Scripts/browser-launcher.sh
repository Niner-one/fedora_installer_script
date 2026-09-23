#!/bin/bash

for browser in brave-browser brave-origin brave firefox zen-browser vivaldi librewolf; do
    if command -v "$browser" >/dev/null 2>&1; then
        exec "$browser" "$@"
    fi
done

if command -v flatpak >/dev/null 2>&1 && flatpak info com.brave.Browser >/dev/null 2>&1; then
    exec flatpak run com.brave.Browser "$@"
fi

if command -v flatpak >/dev/null 2>&1 && flatpak info com.vivaldi.Vivaldi >/dev/null 2>&1; then
    exec flatpak run com.vivaldi.Vivaldi "$@"
fi

if command -v notify-send >/dev/null 2>&1; then
    notify-send "No browser found" "Install Brave, Firefox, Zen Browser, Vivaldi, or LibreWolf."
fi
echo "No browser found; install one or select a browser during installation." >&2
exit 1
