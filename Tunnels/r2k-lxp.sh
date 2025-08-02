#!/bin/bash

PORTS_FILE="/etc/r2k.ports"
LXP_BIN="/usr/local/bin/lxp"
R2K_CMD="/usr/local/bin/r2k-ip"
LOG_DIR="/tmp/r2k_logs"

BLUE="\033[38;5;39m"
WHITE="\033[97m"
GRAY="\033[90m"
BOLD="\033[1m"
RESET="\033[0m"

print_header() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║   🚀 R2K-IP: Beautiful Tunnel Manager via LocalXpose  ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

print_header
echo -e "${WHITE}🔧 Installing LocalXpose CLI...${RESET}"

if [[ ! -f "$LXP_BIN" ]]; then
    curl -s https://api.localxpose.io/api/v2/downloads/lxp-linux-amd64 -o "$LXP_BIN"
    chmod +x "$LXP_BIN"
    echo -e "${BLUE}✅ LocalXpose installed to $LXP_BIN${RESET}"
else
    echo -e "${WHITE}✅ LocalXpose already installed.${RESET}"
fi

echo -ne "${WHITE}🔑 Enter your LocalXpose auth token: ${RESET}"
read -r LXP_TOKEN
"$LXP_BIN" authtoken "$LXP_TOKEN"

echo -e "\n${WHITE}📦 Creating r2k-ip tunnel manager...${RESET}"

sudo tee "$R2K_CMD" > /dev/null << 'EOF'
#!/bin/bash

PORTS_FILE="/etc/r2k.ports"
LOG_DIR="/tmp/r2k_logs"
LXP_BIN="/usr/local/bin/lxp"
mkdir -p "$LOG_DIR"

BLUE="\033[38;5;39m"
WHITE="\033[97m"
GRAY="\033[90m"
BOLD="\033[1m"
RESET="\033[0m"

print_header() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔════════════════════════════════════════════╗"
    echo "║    🌐  R2K-IP TUNNEL MANAGER by R2K.DEV    ║"
    echo "╚════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

add_port() {
    local port=$1
    local type=$2

    print_header

    if [[ -z "$port" ]]; then
        echo -e "${WHITE}❌ Please provide a port.${RESET}"
        exit 1
    fi

    if [[ "$type" != "http" && "$type" != "tcp" ]]; then
        type="tcp"
    fi

    echo -e "${WHITE}🔌 Creating ${type^^} tunnel on port ${port}...${RESET}"
    local log_file="${LOG_DIR}/r2k_${type}_${port}.log"
    nohup "$LXP_BIN" tunnel "$type" --port "$port" > "$log_file" 2>&1 &

    sleep 3
    url=$(grep -Eo 'https?://[^ ]+|tcp://[^ ]+' "$log_file" | head -n 1)

    if [[ -z "$url" ]]; then
        echo -e "${WHITE}❌ Failed to start tunnel for port $port${RESET}"
        exit 1
    fi

    echo "${port}:${type}:${url}" >> "$PORTS_FILE"
    echo -e "${BLUE}✅ ${type^^} tunnel exposed: $url${RESET}"
}

remove_port() {
    local port=$1
    print_header

    if [[ -z "$port" ]]; then
        echo -e "${WHITE}❌ Provide a port to remove.${RESET}"
        exit 1
    fi

    pkill -f "lxp tunnel .* --port $port" >/dev/null 2>&1
    sed -i "/^${port}:/d" "$PORTS_FILE"
    rm -f "${LOG_DIR}/r2k_"*"_${port}.log"

    echo -e "${BLUE}🗑️  Removed tunnel on port $port${RESET}"
}

list_ports() {
    print_header

    if [[ ! -f "$PORTS_FILE" || ! -s "$PORTS_FILE" ]]; then
        echo -e "${WHITE}⚠️  No active tunnels.${RESET}"
        exit 0
    fi

    echo -e "${WHITE}${BOLD}📦 Active Tunnels${RESET}"
    echo -e "${GRAY}───────────────────────────────────────────────────────────────${RESET}"
    printf "${BLUE}🔹 %-6s │ %-5s │ %-40s${RESET}\n" "Port" "Type" "Public URL"
    echo -e "${GRAY}───────────────────────────────────────────────────────────────${RESET}"

    while IFS= read -r line; do
        port=$(echo "$line" | cut -d':' -f1)
        type=$(echo "$line" | cut -d':' -f2)
        url=$(echo "$line" | cut -d':' -f3-)
        printf "🔹 %-6s │ %-5s │ %-40s\n" "$port" "$type" "$url"
    done < "$PORTS_FILE"

    echo -e "${GRAY}───────────────────────────────────────────────────────────────${RESET}"
}

refresh_ports() {
    print_header

    echo -e "${WHITE}🔄 Restarting saved tunnels...${RESET}"

    if [[ ! -f "$PORTS_FILE" || ! -s "$PORTS_FILE" ]]; then
        echo -e "${WHITE}⚠️  No tunnels saved.${RESET}"
        exit 0
    fi

    local ports=$(cat "$PORTS_FILE")
    > "$PORTS_FILE"

    while IFS= read -r line; do
        port=$(echo "$line" | cut -d':' -f1)
        type=$(echo "$line" | cut -d':' -f2)
        add_port "$port" "$type"
    done <<< "$ports"

    echo -e "${BLUE}✅ All tunnels restarted.${RESET}"
}

show_help() {
    print_header
    echo -e "${WHITE}${BOLD}Usage:${RESET} r2k-ip {add|remove|list|refresh} [port] [type]"
    echo ""
    echo -e "${BLUE}Commands:${RESET}"
    echo -e "  🔹 ${BOLD}add <port> [tcp|http]${RESET}     ${WHITE}Expose new tunnel${RESET}"
    echo -e "  🔹 ${BOLD}remove <port>${RESET}             ${WHITE}Stop tunnel on given port${RESET}"
    echo -e "  🔹 ${BOLD}list${RESET}                      ${WHITE}Show all active tunnels${RESET}"
    echo -e "  🔹 ${BOLD}refresh${RESET}                   ${WHITE}Restart all saved tunnels${RESET}"
    echo ""
}

case "$1" in
    add) add_port "$2" "$3" ;;
    remove) remove_port "$2" ;;
    list) list_ports ;;
    refresh) refresh_ports ;;
    *) show_help; exit 1 ;;
esac
EOF

chmod +x "$R2K_CMD"

echo -e "\n${WHITE}🔁 Creating systemd service...${RESET}"
sudo tee /etc/systemd/system/r2k-ip-refresh.service > /dev/null <<EOF
[Unit]
Description=Refresh r2k-ip tunnels after boot
After=network.target

[Service]
ExecStart=$R2K_CMD refresh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable r2k-ip-refresh

echo -e "\n${BLUE}${BOLD}🎉 Setup Complete! Commands:${RESET}"
echo -e "${WHITE}──────────────────────────────────────────────${RESET}"
echo -e "🔹 ${BOLD}r2k-ip add 3000 http${RESET}     → Expose HTTP port"
echo -e "🔹 ${BOLD}r2k-ip add 25565 tcp${RESET}     → Expose Minecraft port"
echo -e "🔹 ${BOLD}r2k-ip list${RESET}              → Show active tunnels"
echo -e "🔹 ${BOLD}r2k-ip remove 25565${RESET}      → Remove a tunnel"
echo -e "🔹 ${BOLD}r2k-ip refresh${RESET}           → Restart all saved"
echo -e "${WHITE}──────────────────────────────────────────────${RESET}"

# Add self-run
echo -e "\n${WHITE}🛠️  Making script executable and running it again...${RESET}"
chmod +x script.sh
./script.sh
