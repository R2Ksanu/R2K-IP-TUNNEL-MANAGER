#!/bin/bash

#  ▄▀█ ▀█▀ █▀▀ █▀█   █ █▄░█   █▀█ █ █▀█   █ █▀▄ █▀▀
#  █▀█ ░█░ █▄▄ █▄█   █ █░▀█   █▀▄ █ █▄█   █ █▄▀ ██▄
# ┌─────────────────────────────────────────────┐
# │           🚀 R2K-IP TUNNEL MANAGER          │
# ├─────────────────────────────────────────────┤
# │  🛠  Auto HTTP/HTTPS & TCP Tunnel Forwarder │
# │  🔄 Auto-Restart at Boot (systemd service)  │
# │  💡 Made for Minecraft, Web Panels & More   │
# └─────────────────────────────────────────────┘
#
# 💻 Usage:
#   r2kip add 25565 tcp     → Minecraft port
#   r2kip add 3000 http     → Web panel port
#   r2kip list              → View tunnels
#   r2kip remove 3000       → Stop tunnel
#   r2kip refresh           → Restart saved tunnels

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

# Prompt for Ngrok authtoken using retype
echo -n "🔑 Enter your Ngrok authtoken: "
read -s token1
echo
echo -n "🔁 Retype your Ngrok authtoken: "
read -s token2
echo

if [[ "$token1" != "$token2" ]]; then
    echo "❌ Tokens do not match. Exiting."
    exit 1
fi

ngrok config add-authtoken "$token1"

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
    if [[ ! -f "$PORTS_FILE" || ! -s "$PORTS_FILE" ]]; then
        echo -e "🚫 [R2K-IP] No active tunnels found."
        echo "💡 Use: r2kip add <port> [tcp|http] to create one."
        exit 0
    fi

    echo -e "\n📡 [R2K-IP] Active Tunnels"
    echo "┌────────────┬────────┬────────────────────────────────────────┐"
    echo "│  Protocol  │  Port  │               Public URL               │"
    echo "├────────────┼────────┼────────────────────────────────────────┤"

    while IFS= read -r line; do
        local_port=$(echo "$line" | cut -d':' -f1)
        type=$(echo "$line" | cut -d':' -f2)
        url=$(echo "$line" | cut -d':' -f3-)
        printf "│  %-8s │  %-6s │  %-38s │\n" "$type" "$local_port" "$url"
    done < "$PORTS_FILE"

    echo "└────────────┴────────┴────────────────────────────────────────┘"
}

refresh_ports() {
    echo "🔄 Restarting saved tunnels..."
    if [[ ! -f "$PORTS_FILE" || ! -s "$PORTS_FILE" ]]; then
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
echo "  r2kip add 25565 tcp     → expose TCP Minecraft port"
echo "  r2kip list              → show active tunnels"
echo "  r2kip remove 25565      → stop tunnel"
echo "  r2kip refresh           → restart saved tunnels"
echo ""
