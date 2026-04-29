# =============================================================================
# vpc.tf
# CISC 886 — Cloud Computing
# Creates the complete network stack:
#   VPC → Public Subnet → Internet Gateway → Route Table → Security Group
# =============================================================================

# -----------------------------------------------------------------------------
# 1. VPC
# A VPC is a logically isolated virtual network within AWS.
# We create a new one (the default VPC is not allowed per project rules).
# enable_dns_hostnames = true is required so EC2 instances get public DNS names,
# which makes SSH and browser access easier to use than raw IP addresses.
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true   # gives EC2s a public DNS name like ec2-X-X-X-X.compute.amazonaws.com

  tags = {
    Name = "${var.netid}-vpc"
  }
}

# -----------------------------------------------------------------------------
# 2. Public Subnet
# A subnet is a range of IP addresses within the VPC.
# map_public_ip_on_launch = true means every EC2 launched here automatically
# gets a public IP — this is what makes the subnet "public" and allows
# internet traffic to reach our Ollama server and OpenWebUI interface.
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true   # auto-assign public IP to instances

  tags = {
    Name = "${var.netid}-subnet-public"
  }
}

# -----------------------------------------------------------------------------
# 3. Internet Gateway
# An Internet Gateway (IGW) allows communication between the VPC and the internet.
# Without it, even instances with public IPs cannot send or receive internet traffic.
# One IGW per VPC is sufficient regardless of the number of subnets.
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.netid}-igw"
  }
}

# -----------------------------------------------------------------------------
# 4. Route Table
# A route table contains rules (routes) that determine where network traffic goes.
# The route 0.0.0.0/0 → IGW means "send all internet-bound traffic to the IGW".
# Without this route, instances in the subnet cannot reach the internet even
# with an IGW attached to the VPC.
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"          # match all traffic (default route)
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.netid}-rt-public"
  }
}

# Associate the route table with our public subnet.
# Until this association exists, the subnet uses the VPC's default route table
# which has no internet route — so this step is required.
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# 5. Security Group
# A security group acts as a virtual firewall controlling inbound and outbound
# traffic for EC2 instances. Rules are STATEFUL — if inbound traffic is allowed,
# the response is automatically allowed outbound without an explicit outbound rule.
#
# Port decisions:
#   22   (SSH)     — restricted to your IP only for secure remote management
#   11434 (Ollama) — the LLM API; restricted to your IP only (not public)
#   3000 (OpenWebUI) — the chat interface; open to all so it can be demoed in a browser
#
# Outbound: allow all — the EC2 needs to download models and Docker images.
# -----------------------------------------------------------------------------
resource "aws_security_group" "ec2_sg" {
  name        = "${var.netid}-sg"
  description = "Security group for InfoSec chatbot EC2 instance"
  vpc_id      = aws_vpc.main.id

  # ── Inbound rules ──────────────────────────────────────────────────────────

  # SSH — port 22
  # Restricted to your IP only (var.my_ip).
  # Allowing SSH from 0.0.0.0/0 is a serious security risk — bots scan
  # the internet constantly for open SSH ports.
  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Ollama API — port 11434
  # Ollama serves the LLM via a REST API on this port.
  # Restricted to your IP — this API has no authentication built in,
  # so exposing it publicly would allow anyone to query your model.
  ingress {
    description = "Ollama API from my IP only"
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # OpenWebUI — port 3000
  # The browser-based chat interface. Open to all (0.0.0.0/0) so it can
  # be accessed from any browser for demos and grading.
  ingress {
    description = "OpenWebUI chat interface"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ── Outbound rules ─────────────────────────────────────────────────────────

  # Allow all outbound traffic.
  # The EC2 instance needs unrestricted outbound access to:
  #   - Download GGUF model from Hugging Face (~800 MB)
  #   - Pull Docker image for OpenWebUI
  #   - Install system packages via apt
  #   - Download Ollama installer
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.netid}-sg"
  }
}
