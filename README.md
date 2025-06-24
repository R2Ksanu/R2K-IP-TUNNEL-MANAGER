🚀 R2K-IP TUNNEL MANAGER
==========================

Effortless HTTP/HTTPS & TCP Tunnel Manager using Ngrok — perfect for Minecraft servers, web panels, and more!
━━━━━━━━━━━━━━━━━━━━
📦 FEATURES
━━━━━━━━━━━━━━━━━━━━
✔️ Auto HTTP/HTTPS & TCP Tunnel Forwarder  
✔️ Auto-Restart on Boot (via systemd)  
✔️ Easy Commands: add | remove | list | refresh  
✔️ Made for Minecraft, Web Panels & More  
━━━━━━━━━━━━━━━━━━
⚙️ INSTALLATION GUIDE
━━━━━━━━━━━━━━━━━━━━
1️⃣ First, install CURL (if not already):

    sudo apt update && sudo apt install -y curl

2️⃣ Clone this repository:

    git clone https://github.com/R2Ksanu/R2K-IP-TUNNEL-MANAGER.git

3️⃣ Enter the directory:

    cd R2K-IP-TUNNEL-MANAGER-

4️⃣ Run the setup script:

    bash r2k-ip.sh

5️⃣ Create a free Ngrok account here:

    https://dashboard.ngrok.com/signup

6️⃣ Get your Ngrok Authtoken from:

    https://dashboard.ngrok.com/get-started/setup/linux

   Example shown by Ngrok:

    ngrok config add-authtoken [YOUR_AUTHTOKEN]

7️⃣ During setup, you will be asked to enter this token.

━━━━━━━━━━━━━━━━━━━
💻 AVAILABLE COMMANDS (AFTER SETUP)
━━━━━━━━━━━━━━━━━━━

➤ Add a new tunnel (TCP or HTTP):

    r2kip add <port> <tcp|http>

    Example:
    r2kip add 25565 tcp     # Minecraft
    r2kip add 3000 http     # Web panel

➤ List all active tunnels:

    r2kip list

➤ Remove a tunnel:

    r2kip remove <port>


➤ Restart saved tunnels:

    r2kip refresh

━━━━━━━━━━━━━━━━━━━━━━━
🎉 ENJOY SECURE TUNNELING WITH R2K-IP! 🎉
━━━━━━━━━━━━━━━━━━━━━━━
