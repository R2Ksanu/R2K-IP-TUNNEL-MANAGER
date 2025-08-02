#!/bin/bash

PORTS_FILE="/etc/r2k.ports"
LOG_DIR="/tmp/r2k_logs"
LXP_BIN="/usr/local/bin/lxp"
mkdir -p "$LOG_DIR"

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"

add_port() {
    local port=$1
    local type=$2

    echo -e "${CYAN}🔌 Adding tunnel for local port: $port (${type})...${RESET}"

    if [[ -z "$port" ]]; then
        echo -e "${RED}❌ Please provide a port.${RESET}"
        exit 1
    fi

    if [[ "$type" != "http" && "$type" != "tcp" ]]; then
        type="tcp"
    fi

    local log_file="${LOG_DIR}/r2k_${type}_${port}.log"
    nohup "$LXP_BIN" tunnel "$type" --port "$port" > "$log_file" 2>&1 &

    sleep 3
    url=$(grep -Eo 'https?://[^ ]+|tcp://[^ ]+' "$log_file" | head -n 1)

    if [[ -z "$url" ]]; then
        echo -e "${RED}❌ Failed to start tunnel for port $port${RESET}"
        exit 1
    fi

    echo "${port}:${type}:${url}" >> "$PORTS_FILE"
    echo -e "${GREEN}✅ Local ${type^^} port ${port} exposed at: $url${RESET}"
}

remove_port() {
    local port=$1
    echo -e "${YELLOW}⚙️  Removing tunnel on port $port...${RESET}"

    if [[ -z "$port" ]]; then
        echo -e "${RED}❌ Provide a port to remove.${RESET}"
        exit 1
    fi

    pkill -f "lxp tunnel .* --port $port" >/dev/null 2>&1
    sed -i "/^${port}:/d" "$PORTS_FILE"
    rm -f "${LOG_DIR}/r2k_"*"_${port}.log"
    echo -e "${GREEN}✅ Removed tunnel for port ${port}${RESET}"
}

list_ports() {
    if [[ ! -f "$PORTS_FILE" ]]; then
        echo -e "${YELLOW}⚠️  No active tunnels.${RESET}"
        exit 0
    fi

    echo -e "${BOLD}📋 Active r2k Tunnels:${RESET}"
    printf "${CYAN}%-10s %-6s %-60s${RESET}\n" "Port" "Type" "Public URL"
    echo -e "${CYAN}----------------------------------------------------------------------${RESET}"
    while IFS= read -r line; do
        local_port=$(echo "$line" | cut -d':' -f1)
        type=$(echo "$line" | cut -d':' -f2)
        url=$(echo "$line" | cut -d':' -f3-)
        printf "🔹 %-8s %-6s %-60s\n" "$local_port" "$type" "$url"
    done < "$PORTS_FILE"
}

refresh_ports() {
    echo -e "${CYAN}🔄 Restarting saved tunnels...${RESET}"

    if [[ ! -f "$PORTS_FILE" ]]; then
        echo -e "${YELLOW}⚠️  No tunnels saved.${RESET}"
        exit 0
    fi

    local ports=$(cat "$PORTS_FILE")
    > "$PORTS_FILE"

    while IFS= read -r line; do
        local_port=$(echo "$line" | cut -d':' -f1)
        type=$(echo "$line" | cut -d':' -f2)
        add_port "$local_port" "$type"
    done <<< "$ports"

    echo -e "${GREEN}✅ All tunnels restarted.${RESET}"
}

show_help() {
    echo -e "${BOLD}Usage:${RESET} r2k-ip {add|remove|list|refresh} [port] [type]"
    echo ""
    echo -e "${CYAN}Commands:${RESET}"
    echo -e "  ${GREEN}add <port> [tcp|http]${RESET}      → expose a new tunnel"
    echo -e "  ${YELLOW}remove <port>${RESET}               → stop and remove a tunnel"
    echo -e "  ${CYAN}list${RESET}                        → list active tunnels"
    echo -e "  ${CYAN}refresh${RESET}                     → restart all saved tunnels"
    echo ""
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
        show_help
        exit 1
        ;;
esac
