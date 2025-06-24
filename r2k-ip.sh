#!/bin/bash

# r2k-ip.sh - Installer for r2kip with HTTP support + auto-start via systemd

# ─────────────────────────────────────────────────────────────

# Colors
RED='\033[0;31m'
ORANGE='\033[0;33m' # Approximated using yellow
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ASCII Art Header
ascii_art="
${RED}  ▄▀█ ▀█▀ █▀▀ █▀█   █ █▄░█   █▀█ █ █▀█   █ █▀▄ █▀▀${NC}
${ORANGE}  █▀█ ░█░ █▄▄ █▄█   █ █░▀█   █▀▄ █ █▄█   █ █▄▀ ██▄${NC}
${BLUE} ┌─────────────────────────────────────────────┐
 │           🚀 R2K-IP TUNNEL MANAGER          │
 ├─────────────────────────────────────────────┤
 │  🛠  Auto HTTP/HTTPS & TCP Tunnel Forwarder │
 │  🔄 Auto-Restart at Boot (systemd service)  │
 │  💡 Made for Minecraft, Web Panels & More   │
 └─────────────────────────────────────────────┘${NC}

💻 ${RED}Usage:${NC}
  ${ORANGE}r2kip add 25565 tcp${NC}     → Minecraft port
  ${ORANGE}r2kip add 3000 http${NC}     → Web panel port
  ${BLUE}r2kip list${NC}              → View tunnels
  ${RED}r2kip remove 3000${NC}       → Stop tunnel
  ${BLUE}r2kip refresh${NC}           → Restart saved tunnels
"

# Clear the screen
clear

# Check for root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run this script as root.${NC}"
  exit 1
fi

# Display ASCII Art
echo -e "$ascii_art"

PORTS_FILE="/etc/ngrok.ports"
NGROK_BIN="/usr/bin/ngrok"
R2K_CMD="/usr/local/bin/r2kip"
LOG_DIR="/tmp/ngrok_logs"

echo "🚀 Installing Ngrok..."

if [[ ! -f "$NGROK_BIN" ]]; then
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
    sudo apt update
    sudo apt install -y ngrok
else
    echo "✅ Ngrok already installed."
fi

# Install jq for parsing Ngrok API responses
sudo apt install -y jq

read -p "🔑 Enter your Ngrok authtoken: " NGROK_TOKEN
ngrok config add-authtoken "$NGROK_TOKEN"

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

    # Wait up to 5s for ngrok API to respond
    for i in {1..10}; do
        sleep 0.5
        url=$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[] | select(.config.addr | test("'$port'$")) | .public_url')
        if [[ -n "$url" && "$url" != "null" ]]; then
            break
        fi
    done

    if [[ -z "$url" || "$url" == "null" ]]; then
        echo "❌ Failed to start ngrok tunnel for port $port"
        exit 1
    fi

    echo "${port}:${type}:${url}" >> "$PORTS_FILE"
    echo "✅ Local ${type} port ${port} exposed at: ${url}"
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
    while IFS= read -r line; do
        local_port=$(echo "$line" | cut -d':' -f1)
        type=$(echo "$line" | cut -d':' -f2)
        url=$(echo "$line" | cut -d':' -f3-)
        echo "🔹 $type port $local_port → $url"
    done < "$PORTS_FILE"
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
    add)
        add_port "$2" "$3"
        ;;
    remove)
        remove_port "$2"
        ;;
    list)
        list_ports
        ;;
    refresh)
        refresh_ports
        ;;
    *)
        echo "Usage: r2kip {add|remove|list|refresh} [port] [type:tcp|http]"
        exit 1
        ;;
esac
EOF

sudo chmod +x "$R2K_CMD"

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

echo ""
echo "✅ Setup complete! Commands:"
echo "  r2kip add 3000 http     → expose HTTP panel"
echo "  r2kip add 25565         → expose TCP Minecraft port"
echo "  r2kip list              → show active tunnels"
echo "  r2kip remove 25565      → stop tunnel"
echo "  r2kip refresh           → restart saved tunnels"
echo ""
