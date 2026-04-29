#!/bin/bash
# =============================================================================
# verify_autostart.sh
# CISC 886 — Cloud Computing
#
# Run this script AFTER rebooting the EC2 instance to prove that both
# Ollama and OpenWebUI start automatically without manual intervention.
# Screenshot the output and include it in Section 7 of your report.
#
# How to use:
#   1. SSH into your EC2 instance
#   2. Run: sudo reboot
#   3. Wait ~60 seconds, then SSH back in
#   4. Run: bash verify_autostart.sh
# =============================================================================

echo ""
echo "============================================================"
echo "  CISC 886 — Auto-Start Verification"
echo "  Run after reboot to confirm services started automatically"
echo "============================================================"
echo ""

# ── Check Ollama ──────────────────────────────────────────────────────────────
echo "[ Ollama Service ]"
OLLAMA_STATUS=$(sudo systemctl is-active ollama)
OLLAMA_ENABLED=$(sudo systemctl is-enabled ollama)
echo "  Active  : $OLLAMA_STATUS"
echo "  Enabled : $OLLAMA_ENABLED"

if [ "$OLLAMA_STATUS" = "active" ]; then
    echo "  API     : $(curl -s http://localhost:11434)"
    echo "  Models  :"
    ollama list | sed 's/^/    /'
else
    echo "  ⚠️  Ollama is NOT running. Start it with: sudo systemctl start ollama"
fi

echo ""

# ── Check OpenWebUI Docker container ─────────────────────────────────────────
echo "[ OpenWebUI Container ]"
WEBUI_STATUS=$(sudo docker inspect open-webui --format '{{.State.Status}}' 2>/dev/null || echo "not found")
RESTART_POLICY=$(sudo docker inspect open-webui --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo "n/a")
echo "  Status         : $WEBUI_STATUS"
echo "  Restart policy : $RESTART_POLICY"

if [ "$WEBUI_STATUS" = "running" ]; then
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    echo "  URL            : http://${PUBLIC_IP}:3000"
else
    echo "  ⚠️  OpenWebUI is NOT running."
    echo "  Restart with  : sudo docker start open-webui"
fi

echo ""

# ── System uptime (proves this is after a reboot) ─────────────────────────────
echo "[ System Info ]"
echo "  Uptime  : $(uptime -p)"
echo "  Booted  : $(who -b | awk '{print $3, $4}')"
echo ""

# ── Final verdict ─────────────────────────────────────────────────────────────
if [ "$OLLAMA_STATUS" = "active" ] && [ "$WEBUI_STATUS" = "running" ]; then
    echo "✅ Both services started automatically after reboot."
    echo "   This satisfies the Section 7 auto-start requirement."
else
    echo "⚠️  One or more services did not start automatically."
    echo "   Check logs: sudo journalctl -u ollama -n 50"
fi

echo "============================================================"
