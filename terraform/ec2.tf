# =============================================================================
# ec2.tf
# CISC 886 — Cloud Computing
# Provisions the EC2 instance that will serve the fine-tuned InfoSec model.
# =============================================================================

# -----------------------------------------------------------------------------
# Data source: look up the latest Amazon Linux 2023 AMI automatically.
# Using a data source instead of a hard-coded AMI ID means the code works
# across regions and stays up to date without manual changes.
# We use Amazon Linux 2023 because:
#   - It is officially supported by the NVIDIA CUDA drivers for g4dn instances
#   - It ships with AWS CLI pre-installed
#   - It is free and well-maintained
# -----------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance
# t3.large
# This matches the resource guide's recommendation for serving sub-10B models.
# The T4 GPU allows Ollama to run inference significantly faster than CPU-only.
#
# user_data is a shell script that runs once when the instance first boots.
# It installs NVIDIA drivers, Ollama, and sets up OpenWebUI as a systemd
# service so it starts automatically on every reboot (Section 7 requirement).
# -----------------------------------------------------------------------------
resource "aws_instance" "infosec_server" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  # Root volume: 100 GB to accommodate:
  #   - NVIDIA drivers (~2 GB)
  #   - Ollama binary + model cache (~2 GB)
  #   - GGUF model file (~800 MB)
  #   - Docker + OpenWebUI image (~2 GB)
  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # ── Bootstrap script (runs once on first boot) ────────────────────────────
  # This installs everything needed to serve the model and the web interface.
  # You will also run the model-specific commands manually via SSH in Step 6,
  # but the infrastructure is ready after this script completes (~5 minutes).
  user_data = <<-EOF
    #!/bin/bash
    set -e
    exec > /var/log/user-data.log 2>&1   # log all output for debugging

    echo "=== Step 1: System update ==="
    dnf update -y
    dnf install -y git curl wget unzip

    echo "=== Step 2: Install NVIDIA drivers (for g4dn T4 GPU) ==="
    dnf install -y kernel-devel kernel-headers
    # CUDA 12 driver for Amazon Linux 2023
    dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
    dnf install -y cuda-drivers
    # Add NVIDIA driver to module path
    echo '/usr/local/cuda/lib64' > /etc/ld.so.conf.d/cuda.conf
    ldconfig

    echo "=== Step 3: Install Ollama ==="
    curl -fsSL https://ollama.ai/install.sh | sh

    # Create ollama systemd service so it starts on reboot
    cat > /etc/systemd/system/ollama.service <<'OLLAMA_SERVICE'
    [Unit]
    Description=Ollama LLM Server
    After=network.target

    [Service]
    Type=simple
    User=root
    ExecStart=/usr/local/bin/ollama serve
    Restart=always
    RestartSec=3
    Environment=OLLAMA_HOST=0.0.0.0

    [Install]
    WantedBy=multi-user.target
    OLLAMA_SERVICE

    systemctl daemon-reload
    systemctl enable ollama
    systemctl start ollama

    echo "=== Step 4: Install Docker (for OpenWebUI) ==="
    dnf install -y docker
    systemctl enable docker
    systemctl start docker

    echo "=== Step 5: Install OpenWebUI via Docker ==="
    # OpenWebUI runs as a Docker container and connects to Ollama on localhost.
    # --restart always ensures it starts automatically on every reboot (Section 7 req).
    docker run -d \
      --name open-webui \
      --restart always \
      -p 3000:8080 \
      -e OLLAMA_BASE_URL=http://localhost:11434 \
      -v open-webui:/app/backend/data \
      ghcr.io/open-webui/open-webui:main

    echo "=== Bootstrap complete ==="
    echo "Ollama is running on port 11434"
    echo "OpenWebUI is running on port 3000"
    echo "SSH in and run: ollama pull <your-model> to load your GGUF model"
  EOF

  tags = {
    Name = "${var.netid}-ec2"
  }
}
