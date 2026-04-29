#!/bin/bash
# =============================================================================
# CISC 886 — Cloud Computing
# EC2 Model Deployment Script
# Run these commands manually over SSH after the bootstrap completes.
# Each section is labelled — copy and paste one block at a time.
# =============================================================================

# ── SECTION 1: Verify services ────────────────────────────────────────────────
# Run these first to confirm Ollama and Docker are healthy.

sudo systemctl status ollama --no-pager
curl http://localhost:11434
sudo docker ps


# ── SECTION 2: Download your GGUF model from Hugging Face ────────────────────
# Hugging Face username for model download
# The model filename ends in .gguf — check your HF repo for the exact name.
# This file is ~800 MB — download takes 2–5 minutes depending on network speed.

HF_USERNAME="Mahmoud-Alsakhawy"
REPO_NAME="infosec-llama3-qlora-gguf"
GGUF_FILE="unsloth.Q4_K_M.gguf"         # <-- check your HF repo for exact filename

mkdir -p /home/ec2-user/models
cd /home/ec2-user/models

wget "https://huggingface.co/${HF_USERNAME}/${REPO_NAME}/resolve/main/${GGUF_FILE}" \
     -O infosec-llama3.gguf \
     --progress=bar:force

echo "✅ Model downloaded: $(du -sh infosec-llama3.gguf)"


# ── SECTION 3: Create the Ollama Modelfile ────────────────────────────────────
# A Modelfile tells Ollama how to load and prompt the model.
# The SYSTEM prompt matches what we used during fine-tuning — this is important
# because the model learned to respond to this exact system message.
# PARAMETER settings control inference behaviour:
#   temperature 0.1 — low = more focused, factual answers (good for Q&A)
#   num_predict 256 — max tokens to generate per response

cat > /home/ec2-user/models/Modelfile <<'MODELFILE'
FROM ./infosec-llama3.gguf

SYSTEM """
You are a knowledgeable and helpful information security expert.
Answer questions clearly, accurately, and concisely.
"""

PARAMETER temperature 0.1
PARAMETER num_predict 256
PARAMETER stop "<|eot_id|>"
PARAMETER stop "<|end_of_text|>"
MODELFILE

echo "✅ Modelfile created."
cat /home/ec2-user/models/Modelfile


# ── SECTION 4: Register the model with Ollama ─────────────────────────────────
# ollama create reads the Modelfile and registers the model under the name
# "infosec-assistant". After this you can query it by that name.
# The name you use here is what will be visible in OpenWebUI (Section 7 requirement).

cd /home/ec2-user/models
ollama create infosec-assistant -f Modelfile

echo "✅ Model registered. Listing available models:"
ollama list


# ── SECTION 5: Test the model via Ollama CLI ──────────────────────────────────
# Quick sanity check before doing the formal curl test.
# You should get a coherent InfoSec answer within a few seconds.

ollama run infosec-assistant "What is the CIA triad?"


# ── SECTION 6: Required curl test (copy output for your report) ──────────────
# The rubric requires a curl call to the running API with the response shown.
# Run this and screenshot the terminal — include it in Section 6 of your report.
# The -s flag suppresses progress output; python3 formats the JSON nicely.

echo "=== CURL TEST — copy this output for your report ==="

curl -s http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "infosec-assistant",
    "prompt": "What is a man-in-the-middle attack and how can it be prevented?",
    "stream": false
  }' | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('Model    :', data.get('model'))
print('Response :', data.get('response'))
print('Done     :', data.get('done'))
print('Tokens   :', data.get('eval_count'))
"


# ── SECTION 7: Verify auto-start is configured ────────────────────────────────
# Both services must start automatically on reboot (Section 7 requirement).
# Run these to confirm — the output should show "enabled" for both.

echo "=== Checking auto-start configuration ==="
sudo systemctl is-enabled ollama
sudo docker inspect open-webui --format '{{.HostConfig.RestartPolicy.Name}}'
# Expected outputs:
#   enabled          (ollama restarts via systemd)
#   always           (open-webui restarts via Docker restart policy)


# ── SECTION 8: Get the terminal screenshot for your report ───────────────────
# Run this block — it prints a summary of everything running.
# Screenshot this entire output and include it in Section 6 of your report.

echo ""
echo "============================================================"
echo "  CISC 886 — InfoSec Chatbot Deployment Summary"
echo "============================================================"
echo "  EC2 Instance   : $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "  Public IP      : $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "  Instance Type  : $(curl -s http://169.254.169.254/latest/meta-data/instance-type)"
echo ""
echo "  Ollama status  : $(sudo systemctl is-active ollama)"
echo "  Ollama models  :"
ollama list
echo ""
echo "  Docker containers:"
sudo docker ps --format "  {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "  OpenWebUI URL : http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
echo "  Ollama API    : http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):11434"
echo "============================================================"
