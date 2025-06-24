#!/bin/bash

# r2k-lxp.sh - Installer for r2kip using LocalXpose (lxp)

PORTS_FILE="/etc/lxp.ports"
LXP_BIN="/usr/local/bin/lxp"
R2K_CMD="/usr/local/bin/r2kip"
LOG_DIR="/tmp/lxp_logs"

echo "🚀 Installing LocalXpose CLI..."

if [[ ! -f "$LXP_BIN" ]]; then
    curl -s https://api.localxpose.io/api/v2/downloads/lxp-linux-amd64 -o "$LXP_BIN"
    chmod +x "$LXP_BIN"
else
    echo "✅ LocalXpose already installed."
fi

read -p "🔑 Enter your LocalXpose auth token: " LXP_TOKEN
"$LXP_BIN" authtoken "$LXP_TOKEN"

echo "📦 Creating r2kip tunnel manager for LocalXpose..."

sudo tee "$R2K_CMD" > /dev/null << 'EOF'
#!/bin/bash

PORTS_FILE="/etc/lxp.ports"
LOG_DIR="/tmp/lxp_logs"
LXP_BIN="/usr/local/bin/lxp"
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

    local log_file="${LOG_DIR}/lxp_${type}_${port}.log"
    nohup "$LXP_BIN" tunnel "$type" --port "$port" > "$log_file" 2>&1 &

    # Wait up to 5s for LocalXpose to start
    sleep 3
    url=$(grep -Eo 'https?://[^ ]+|tcp://[^ ]+' "$log_file" | head -n 1)

    if [[ -z "$url" ]]; then
        echo "❌ Failed to start LocalXpose tunnel for port $port"
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

    pkill -f "lxp tunnel .* --port $port" >/dev/null 2>&1
    sed -i "/^${port}:/d" "$PORTS_FILE"
    rm -f "${LOG_DIR}/lxp_"*"_${port}.log"
    echo "✅ Removed tunnel for port ${port}"
}

list_ports() {
    if [[ ! -f "$PORTS_FILE" ]]; then
        echo "⚠️ No active tunnels."
        exit 0
    fi
    echo "📋 Active LocalXpose Tunnels:"
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
Description=Refresh LocalXpose tunnels after boot
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
echo "  r2kip add 3000 http     → expose HTTP port"
echo "  r2kip add 25565 tcp     → expose Minecraft server"
echo "  r2kip list              → show active tunnels"
echo "  r2kip remove 25565      → stop tunnel"
echo "  r2kip refresh           → restart saved tunnels"
echo ""
