#!/bin/bash

# r2k-ip.sh - Installer for R2K-IP Tunnel Manager

PORTS_FILE="/etc/ngrok.ports"
NGROK_BIN="/usr/bin/ngrok"
R2K_CMD="/usr/local/bin/r2kip"
LOG_DIR="/tmp/ngrok_logs"

# Colors
RED='\033[0;31m'
ORANGE='\033[38;5;208m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ASCII Art Banner
ascii_art="
${RED} ▄▀█▀█▀▀▀█▀█   █ █▄░█   █▀█ █ █▀█   █ █▀▄ █▀▀${NC}
${ORANGE} █▀█░█░░█▄█   █ █░▀█   █▀▄ █ █▄█   █ █▄▀ ██▄${NC}
${BLUE}┌─────────────────────────────────────────────┐${NC}
${BLUE}│${CYAN}           🚀 R2K-IP TUNNEL MANAGER          ${BLUE}│${NC}
${BLUE}├─────────────────────────────────────────────┤${NC}
${BLUE}│${YELLOW}  🛠  Auto HTTP/HTTPS & TCP Tunnel Forwarder ${BLUE}│${NC}
${BLUE}│${YELLOW}  🔄 Auto-Restart at Boot (systemd service)  ${BLUE}│${NC}
${BLUE}│${YELLOW}  💡 Made for Minecraft, Web Panels & More   ${BLUE}│${NC}
${BLUE}└─────────────────────────────────────────────┘${NC}

💻 ${CYAN}Usage:${NC}
  ${GREEN}r2kip add 25565 tcp${NC}     → Minecraft port
  ${GREEN}r2kip add 3000 http${NC}     → Web panel port
  ${GREEN}r2kip list${NC}              → View tunnels
  ${GREEN}r2kip remove 3000${NC}       → Stop tunnel
  ${GREEN}r2kip refresh${NC}           → Restart saved tunnels
"

# Root check
clear
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}❌ Please run this script as root.${NC}"
    exit 1
fi

echo -e "$ascii_art"

# Animated loading bar
function loading_bar() {
    local msg="$1"
    echo -n "🚀 $msg"
    for i in {1..3}; do
        sleep 0.4
        echo -n "."
    done
    echo ""
}

# Install ngrok silently
loading_bar "Installing Ngrok"
if [[ ! -f "$NGROK_BIN" ]]; then
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc > /dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list > /dev/null
    sudo apt update -qq > /dev/null
    sudo apt install -y ngrok > /dev/null 2>&1
else
    echo "✅ Ngrok already installed."
fi

# Install jq silently
sudo apt install -y jq > /dev/null 2>&1

# Ngrok auth token input
read -p "🔑 Enter your Ngrok authtoken: " NGROK_TOKEN
ngrok config add-authtoken "$NGROK_TOKEN" > /dev/null 2>&1

# Check if token works
TMP_LOG="/tmp/ngrok_token_test.log"
nohup ngrok http 12345 > "$TMP_LOG" 2>&1 &
sleep 3
pkill -f "ngrok http 12345" >/dev/null 2>&1

if grep -q "ERR_NGROK" "$TMP_LOG"; then
    echo -e "${RED}❌ Authtoken is invalid!${NC}"
    rm -f "$TMP_LOG"
    exit 1
else
    echo -e "${CYAN}✅ Authtoken works!${NC}"
    rm -f "$TMP_LOG"
fi

# Write r2kip manager
echo "📦 Creating r2kip tunnel manager..."

sudo tee "$R2K_CMD" > /dev/null << 'EOF'
#!/bin/bash

PORTS_FILE="/etc/ngrok.ports"
LOG_DIR="/tmp/ngrok_logs"
mkdir -p "$LOG_DIR"

add_port() {
    local port=$1
    local type=$2
    if [[ -z "$port" ]]; then
        echo "❌ Please provide a port."
        exit 1
    fi

    if [[ "$type" != "http" && "$type" != "tcp" ]]; then
        type="tcp"
    fi

    local log_file="${LOG_DIR}/ngrok_${type}_${port}.log"
    nohup ngrok $type $port > "$log_file" 2>&1 &

    for i in {1..10}; do
        sleep 0.5
        url=$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[] | select(.config.addr | test("'$port'$")) | .public_url')
        if [[ -n "$url" && "$url" != "null" ]]; then break; fi
    done

    if [[ -z "$url" || "$url" == "null" ]]; then
        echo "❌ Failed to start ngrok tunnel for port $port"
        exit 1
    fi

    echo "${port}:${type}:${url}" >> "$PORTS_FILE"
    echo "✅ Local ${type} port ${port} exposed at: ${url}"
    printf "\n"
    printf "┌──────────────┬────────────┬────────────────────────────────────────┐\n"
    printf "│  Protocol    │  Port      │              Public URL                │\n"
    printf "├──────────────┼────────────┼────────────────────────────────────────┤\n"
    printf "│  %-10s │  %-8s │  %-38s │\n" "$type" "$port" "$url"
    printf "└──────────────┴────────────┴────────────────────────────────────────┘\n"
}

remove_port() {
    local port=$1
    if [[ -z "$port" ]]; then
        echo "❌ Provide a port to remove."
        exit 1
    fi

    pkill -f "ngrok .* $port" >/dev/null 2>&1
    sed -i "/^${port}:/d" "$PORTS_FILE"
    rm -f "${LOG_DIR}/ngrok_"*"_${port}.log"
    echo "✅ Removed tunnel for port ${port}"
}

list_ports() {
    if [[ ! -f "$PORTS_FILE" ]]; then
        echo "⚠️ No active tunnels."
        exit 0
    fi
    echo "📋 Active Ngrok Tunnels:"
    printf "\n┌──────────────┬────────────┬────────────────────────────────────────┐\n"
    printf "│  Protocol    │  Port      │              Public URL                │\n"
    printf "├──────────────┼────────────┼────────────────────────────────────────┤\n"
    while IFS= read -r line; do
        local_port=$(echo "$line" | cut -d':' -f1)
        type=$(echo "$line" | cut -d':' -f2)
        url=$(echo "$line" | cut -d':' -f3-)
        printf "│  %-10s │  %-8s │  %-38s │\n" "$type" "$local_port" "$url"
    done < "$PORTS_FILE"
    printf "└──────────────┴────────────┴────────────────────────────────────────┘\n"
}

refresh_ports() {
    echo "🔄 Restarting tunnels..."
    if [[ ! -f "$PORTS_FILE" ]]; then
        echo "⚠️ No tunnels saved."
        exit 0
    fi
    local ports=$(cat "$PORTS_FILE")
    > "$PORTS_FILE"

    while IFS= read -r line; do
        local_port=$(echo "$line" | cut -d':' -f1)
        type=$(echo "$line" | cut -d':' -f2)
        add_port "$local_port" "$type"
    done <<< "$ports"
}

case "$1" in
    add) add_port "$2" "$3" ;;
    remove) remove_port "$2" ;;
    list) list_ports ;;
    refresh) refresh_ports ;;
    *) echo "Usage: r2kip {add|remove|list|refresh} [port] [type:tcp|http]"; exit 1 ;;
esac
EOF

chmod +x "$R2K_CMD"

# Systemd setup
echo "🛠 Setting up systemd auto-start..."

sudo tee /etc/systemd/system/r2kip-refresh.service > /dev/null <<EOF
[Unit]
Description=Refresh ngrok tunnels after boot
After=network.target

[Service]
ExecStart=$R2K_CMD refresh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable r2kip-refresh

echo -e "\n🎉 ${GREEN}Setup complete! You can now use r2kip command.${NC}"
