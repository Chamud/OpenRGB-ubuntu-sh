#!/bin/bash

# OpenRGB SDK server (CLI connects here). Override with env if needed.
SDK_HOST="${SDK_HOST:-0.0.0.0}"
SDK_PORT="${SDK_PORT:-6742}"
OPENRGB_SERVER_PID=""

cleanup() {
    if [[ -n "$OPENRGB_SERVER_PID" ]] && kill -0 "$OPENRGB_SERVER_PID" 2>/dev/null; then
        kill "$OPENRGB_SERVER_PID" 2>/dev/null
        wait "$OPENRGB_SERVER_PID" 2>/dev/null
    fi
}
trap cleanup EXIT INT TERM

sdk_listening() {
    ss -ltn 2>/dev/null | grep -qE ":${SDK_PORT}([[:space:]]|$)"
}

ensure_openrgb_server() {
    if sdk_listening; then
        return 0
    fi
    echo "Starting OpenRGB SDK server on ${SDK_HOST}:${SDK_PORT}..." >&2
    openrgb --server-host "$SDK_HOST" --server-port "$SDK_PORT" --server &
    OPENRGB_SERVER_PID=$!
    local i
    for ((i = 0; i < 50; i++)); do
        if sdk_listening; then
            return 0
        fi
        sleep 0.1
    done
    echo "OpenRGB server did not listen on port ${SDK_PORT} in time." >&2
    return 1
}

ensure_openrgb_server || exit 1

get_temp() {
    sensors 2>/dev/null | grep -i 'Tctl' | head -1 | awk '{print $2}' | tr -d '+°C'
}

get_rgb() {
    t=$1

    if (( $(echo "$t <= 30" | bc -l) )); then
        R=0; G=40; B=0

    elif (( $(echo "$t <= 45" | bc -l) )); then
        # Green → Blue
        ratio=$(echo "($t-30)/15" | bc -l)
        R=0
        G=$(printf "%.0f" $(echo "40*(1-$ratio)" | bc -l))
        B=$(printf "%.0f" $(echo "40*$ratio" | bc -l))

    elif (( $(echo "$t <= 70" | bc -l) )); then
        # Blue → Red
        ratio=$(echo "($t-45)/25" | bc -l)
        R=$(printf "%.0f" $(echo "40*$ratio" | bc -l))
        G=0
        B=$(printf "%.0f" $(echo "40*(1-$ratio)" | bc -l))

    else
        R=40; G=0; B=0
    fi

    echo "$R $G $B"
}

while true; do
    temp=$(get_temp)
    if [[ -z "$temp" ]] || ! [[ "$temp" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Could not read CPU temp (Tctl); retrying..." >&2
        sleep 2
        continue
    fi

    read -r R G B <<< "$(get_rgb "$temp")"
    color=$(printf '%02X%02X%02X' "$R" "$G" "$B")

    echo "Temp: ${temp}°C → RGB: $R $G $B (#$color)"

    openrgb --device 0 --mode direct --color "$color"

    sleep 2
done