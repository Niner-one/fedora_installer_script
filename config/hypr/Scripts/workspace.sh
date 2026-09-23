#!/bin/bash

sleep 0.05

## Fetch active workspace and monitor
ACTIVE_WS_JSON=$(hyprctl activeworkspace -j) || exit 1
CURRENT_ID=$(jq -er '.id | select(type == "number")' <<< "$ACTIVE_WS_JSON") || exit 1
FOCUSED_MONITOR_NAME=$(jq -er '.monitor | select(type == "string")' <<< "$ACTIVE_WS_JSON") || exit 1
FOCUSED_MONITOR_ID=$(jq -er '.monitorID | select(type == "number")' <<< "$ACTIVE_WS_JSON") || exit 1

## Per-monitor debouncing
if [[ ! -d "${XDG_RUNTIME_DIR:-}" ]]; then
    echo "XDG_RUNTIME_DIR is unavailable; cannot debounce workspace switching." >&2
    exit 1
fi
LOCK_FILE="$XDG_RUNTIME_DIR/hypr-workspace-next-${FOCUSED_MONITOR_ID}.lock"
NOW_MS=$(date +%s%3N)

if [ -f "$LOCK_FILE" ]; then
    LAST_MS=$(cat "$LOCK_FILE" 2>/dev/null)
    if [[ "$LAST_MS" =~ ^[0-9]+$ ]] && [ $((NOW_MS - LAST_MS)) -lt 250 ]; then
        exit 0
    fi
fi

echo "$NOW_MS" > "$LOCK_FILE"

focus_workspace() {
    local ws="$1"
    if [[ "$ws" =~ ^[0-9]+$ ]]; then
        hyprctl dispatch "hl.dsp.focus({ workspace = $ws })"
    else
        hyprctl dispatch "hl.dsp.focus({ workspace = \"$ws\" })"
    fi
}

CURRENT_WINDOWS=$(echo "$ACTIVE_WS_JSON" | jq -r '.windows')
if [ -z "$CURRENT_WINDOWS" ] || [ "$CURRENT_WINDOWS" = "null" ]; then
    CURRENT_WINDOWS=0
fi

## Get active workspace IDs assigned to current monitor
ACTIVE_IDS_LIST=$(hyprctl workspaces -j | \
    jq -r --arg monitor "$FOCUSED_MONITOR_NAME" --argjson monitor_id "$FOCUSED_MONITOR_ID" '.[] | select(.monitor == $monitor or .monitorID == $monitor_id) | select(.windows > 0) | .id' | \
    sort -n)

## Extract workspace IDs from workspace rules for current monitor
RULE_IDS_LIST=$(hyprctl workspacerules -j 2>/dev/null | \
    jq -r --arg monitor "$FOCUSED_MONITOR_NAME" '.[] | select(.monitor == $monitor) | .workspaceString' | \
    grep -E '^[0-9]+$' | sort -n)

## Combine active workspaces and workspace rules for current monitor
COMBINED_MONITOR_IDS=$(printf "%s\n%s" "$ACTIVE_IDS_LIST" "$RULE_IDS_LIST" | grep -v '^$' | sort -nu)

ALL_IDS_LIST=$(hyprctl workspaces -j | jq -r '.[].id' | sort -n)

mapfile -t ACTIVE_IDS < <(printf "%s\n" "$ACTIVE_IDS_LIST")
mapfile -t MONITOR_RULE_IDS < <(printf "%s\n" "$COMBINED_MONITOR_IDS")

TARGET_ID=""

## Cycle through already active/open workspaces on current display
NEXT_TARGET_FOUND="false"
for id in "${ACTIVE_IDS[@]}"; do
    if [ "$id" -gt "$CURRENT_ID" ]; then
        TARGET_ID=$id
        NEXT_TARGET_FOUND="true"
        break
    fi
done

## If no higher active workspace, use workspace rule or find next bound workspace
if [ "$NEXT_TARGET_FOUND" == "false" ]; then
    if [ "$CURRENT_WINDOWS" -eq 0 ] && [ ${#ACTIVE_IDS[@]} -gt 0 ]; then
        # Wrap around to lowest active workspace on this monitor
        TARGET_ID="${ACTIVE_IDS[0]}"
    else
        ## Find next workspace assigned to this monitor by rules
        for id in "${MONITOR_RULE_IDS[@]}"; do
            if [ "$id" -gt "$CURRENT_ID" ]; then
                TARGET_ID=$id
                NEXT_TARGET_FOUND="true"
                break
            fi
        done

        ## If we reached the end of workspace rules, wrap to lowest assigned or search forward
        if [ "$NEXT_TARGET_FOUND" == "false" ]; then
            if [ ${#MONITOR_RULE_IDS[@]} -gt 0 ]; then
                TARGET_ID="${MONITOR_RULE_IDS[0]}"
            else
                # Fallback: Find next uncreated ID
                TARGET_ID=$((CURRENT_ID + 1))
                while grep -qx "$TARGET_ID" <<< "$ALL_IDS_LIST"; do
                    TARGET_ID=$((TARGET_ID + 1))
                done
            fi
        fi
    fi
fi

focus_workspace "$TARGET_ID"
