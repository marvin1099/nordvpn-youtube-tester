#!/usr/bin/env bash

# === CONFIG ===
MAX_TRIES=20
VIDEO_URL="https://youtu.be/C0DPdy98e4c"
WORKING_FILE="$HOME/.config/nordvpn_youtube_working.txt"
FALLBACK_COUNTRY="Germany"

# Needed Tools
YTDLP="yt-dlp"
NORDVPN="nordvpn"
CURL="curl"
GREP="grep"
TR="tr"
AWK="awk"
SED="sed"

if [[ -n "$1" ]]; then
    SET_COUNTRY=$1
fi

if [[ -n "$2" ]]; then
    CURRENT=1
fi

if [[ -n "$3" ]]; then
    #threshold: ~375 KB/s = ~3 Mbps for 720p streaming
    NEEDED_SPEED=${3:-375000}
fi

# List of required commands
REQUIRED_CMDS=("$NORDVPN" "$YTDLP" "$CURL" "$GREP" "$TR" "$AWK" "$SED")

# Track missing commands
MISSING_CMDS=()

# Check each command
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_CMDS+=("$cmd")
    fi
done

# Report if anything is missing
if (( ${#MISSING_CMDS[@]} > 0 )); then
    echo "❌ The following required commands are missing:"
    echo "❌ ${MISSING_CMDS[*]}"
    exit 1
fi

# Check for the ping command
if ! command -v "ping" &>/dev/null; then
    echo "❌ Ping command missing. Exiting."
    exit 1
fi

# Check for internet
if ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    echo "❌ No internet connection detected. Exiting."
    exit 1
fi

if [[ -z "$SET_COUNTRY" ]]; then
    # Get the public IP address
    IP=$("$CURL" -s "https://api.ipify.org")

    # Get the country information using a geolocation API
    COUNTRY=$("$CURL" -s "https://ipapi.co/${IP}/country_name/")
else
    COUNTRY=$SET_COUNTRY
fi

FALLBACK_COUNTRY="${FALLBACK_COUNTRY//\_/ }"
COUNTRY="${COUNTRY//\_/ }"
NORDVPN_COUNTRY="${COUNTRY// /_}"
if [[ -z "$COUNTRY" ]] || ! "$NORDVPN" countries | "$TR" -s '[:space:]' '\n' | "$GREP" -Fxq "$NORDVPN_COUNTRY"; then
    if [[ -n "$COUNTRY" ]]; then
        echo "❌ Country $COUNTRY is not supported by NordVPN"
    else
        echo "❌ No country Location was found"
    fi
    echo "❌ Using fallback country $FALLBACK_COUNTRY."
    COUNTRY=$FALLBACK_COUNTRY
    NORDVPN_COUNTRY="${COUNTRY// /_}"
fi

echo "🔍 Searching for a NordVPN server that allows YouTube video access in $COUNTRY..."

mkdir -p "$(dirname "$WORKING_FILE")"
touch "$WORKING_FILE"

USE_SAVED_NEXT=-1 # try 2 random country servers (-1,0)
SAVED_SERVERS=($(<"$WORKING_FILE"))
SAVED_INDEX=${RANDOM:-0}
CONNECTED_PREFIX=""

try_server() {
    local server="$1"
    if [[ -n "$server" ]]; then
        echo "⏳ Connecting to server: $server"
        "$NORDVPN" c "$server" >/dev/null 2>&1 &
        sleep 4
    fi

    # Wait for connection
    for attempt in {1..10}; do
        sleep 2
        if "$NORDVPN" status | "$GREP" -q "Status: Connected"; then
            echo "    ✅ VPN connected."
            break
        fi
    done

    if ! "$NORDVPN" status | "$GREP" -q "Status: Connected"; then
        echo "    ❌ Failed to establish VPN connection to $server."
        return 1
    fi

    if [[ -n "$NEEDED_SPEED" && "$NEEDED_SPEED" -gt 0 ]]; then
        echo "    📶 Testing server speed..."
        SPEED_BPS=$("$CURL" -s -w "%{speed_download}" -o /dev/null --max-time 8 "https://speed.cloudflare.com/__down?bytes=10000000")

        if [[ -z "$SPEED_BPS" || "$SPEED_BPS" -lt $NEEDED_SPEED ]]; then
            if [ "${SPEED_BPS:-0}" -lt 1024 ]; then
                echo "    ❌ Server too slow (${SPEED_BPS} B/s)."
            else
                SPEED_KB=$((SPEED_BPS / 1024))
                echo "    ❌ Server too slow (${SPEED_KB} KB/s)."
            fi
            return 2
        fi

        echo "    ✅ Server speed OK ($((SPEED_BPS / 1024)) KB/s)"
    fi

    return 0
}

for i in $(seq 1 $MAX_TRIES); do
    echo "⏳ [$i/$MAX_TRIES] Checking server..."
    status="$("$NORDVPN" status)"
    if [[ -z "$CONNECTED_PREFIX" && "$(echo "$status" | "$GREP" "Status: Connected")" ]]; then
        # Get current server hostname prefix (2 first letters)
        country_name=$(echo "$status" | "$AWK" -F': ' '/Server: / {sub(/ #.*/, "", $2); print $2}' | "$SED" 's/^[[:space:]]*//;s/[[:space:]]*$//') #'
        if [[ "$country_name" == "$COUNTRY" ]]; then
            # Get current server hostname prefix (2 first letters)
            server_hostname=$(echo "$status" | "$AWK" -F': ' '/Hostname: / {print $2}')
            CONNECTED_PREFIX="${server_hostname:0:2}"
        fi
    fi

    if [[ "$i" -eq 1 && "$(echo "$status" | "$GREP" "Status: Connected")" && -n "$CURRENT" ]]; then
        echo "    🔵 Using current connection..."
        try_server || {
            server_hostname=$(echo "$status" | "$AWK" -F': ' '/Hostname: / {print $2}')
            server_name="${server_hostname%%.*}"
            # remove if connection fails
            "$SED" -i "/^$server_name$/d" "$WORKING_FILE"
            continue
        }
    else
        if [[ "$USE_SAVED_NEXT" -gt 0 && ${#SAVED_SERVERS[@]} -gt 0 ]]; then
            # Use only saved servers matching prefix
            SERVER=""
            if [[ -n "$CONNECTED_PREFIX" ]]; then
                if [[ -z $start_index ]]; then
                    start_index=$(( SAVED_INDEX % ${#SAVED_SERVERS[@]} ))
                fi
                while [[ -z "$SERVER" ]]; do
                    candidate="${SAVED_SERVERS[$SAVED_INDEX]}"
                    SAVED_INDEX=$(( (SAVED_INDEX + 1) % ${#SAVED_SERVERS[@]} ))

                    if [[ "${candidate:0:2}" == "$CONNECTED_PREFIX" ]]; then
                        SERVER="$candidate"
                        break
                    fi

                    # If we came full circle, no matching server found
                    if [[ $SAVED_INDEX -eq $start_index ]]; then
                        break
                    fi
                done
                if [[ -n "$SERVER" ]]; then
                    # next time use a country server
                    if [[ $USE_SAVED_NEXT -gt 2 ]]; then
                        USE_SAVED_NEXT=$((USE_SAVED_NEXT - 1))
                    elif [[ $USE_SAVED_NEXT -eq 1 ]]; then
                        USE_SAVED_NEXT=0 # if set lower would use more random servers
                    fi
                fi
            fi
        else
            SERVER=""
            if [[ $USE_SAVED_NEXT -lt 0 ]]; then
                USE_SAVED_NEXT=$((USE_SAVED_NEXT + 1))
            elif [[ $USE_SAVED_NEXT -eq 0 ]]; then
                USE_SAVED_NEXT=1 # if set higher would use more saved servers
            fi
        fi

        #"$NORDVPN" disconnect >/dev/null 2>&1
        if [[ -n "$SERVER" ]]; then
            try_server "$SERVER" || {
                # remove if connection fails
                "$SED" -i "/^$SERVER$/d" "$WORKING_FILE"
                continue
            }
        else
            if [[ -n "$NORDVPN_COUNTRY" ]]; then
                "$NORDVPN" connect "$NORDVPN_COUNTRY" >/dev/null 2>&1 &
            else
                "$NORDVPN" connect >/dev/null 2>&1 &
            fi

            try_server || {
                status="$("$NORDVPN" status)"
                server_hostname=$(echo "$status" | "$AWK" -F': ' '/Hostname: / {print $2}')
                server_name="${server_hostname%%.*}"
                # remove if connection fails
                "$SED" -i "/^$server_name$/d" "$WORKING_FILE"
                continue
            }
        fi
    fi

    # Check video access
    echo "    🔵 Testing YouTube video access..."
    out="$(timeout 20 "$YTDLP" --quiet --no-playlist --simulate "$VIDEO_URL" 2>&1)"

    if [[ $? -eq 0 ]]; then
        echo "✅ Success: Video is accessible!"

        # Get server info
        status="$("$NORDVPN" status)"
        echo "$status" | "$AWK" '/Server: / || /Hostname: / || /IP: / {print "    🟣 " $0}'

        # Only record if country matches exactly
        country_name=$(echo "$status" | "$AWK" -F': ' '/Server: / {sub(/ #.*/, "", $2); print $2}' | "$SED" 's/^[[:space:]]*//;s/[[:space:]]*$//') #'
        if [[ "$country_name" == "$COUNTRY" ]]; then
            server_hostname=$(echo "$status" | "$AWK" -F': ' '/Hostname: / {print $2}')
            server_name="${server_hostname%%.*}"
            if ! "$GREP" -qx "$server_name" "$WORKING_FILE"; then
                echo "$server_name" >> "$WORKING_FILE"
                echo "    📝 Saved working server: $server_name"
            fi
        fi

        #notify-send "NordVPN" "✅ YouTube video is accessible!"
        exit 0
    else
        echo "❌ Blocked or failed."
        status="$("$NORDVPN" status)"
        echo "$status" | "$AWK" '/Server: / || /Hostname: / || /IP: / {print "    🟣 " $0}'

        # Remove from working list if previously saved and failed
        if [[ -n "$SERVER" ]]; then
            "$SED" -i "/^$SERVER$/d" "$WORKING_FILE"
            echo "    ❌ Removed $SERVER from saved servers."
        fi

        sleep 2
    fi
done

echo "❌ No working YouTube video server found in $MAX_TRIES tries."
#notify-send "NordVPN" "❌ No working YouTube video server found."
exit 1
