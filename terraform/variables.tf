# =============================================================================
# variables.tf
# CISC 886 — Cloud Computing
# All configurable values in one place — change only this file for your setup.
# =============================================================================

variable "netid" {
  description = "Your Queen's University netID. Used as a prefix on every AWS resource."
  type        = string
  default     = "group1"
}

variable "aws_region" {
  description = "AWS region for all resources. Must match the region your EMR/S3 used."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = <<-EOT
    CIDR block for the VPC.
    /16 gives 65,536 addresses — enough room to add more subnets in future
    without re-architecting the network.
  EOT
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = <<-EOT
    CIDR block for the public subnet.
    /24 gives 256 addresses. We use a public subnet (not private) because
    our EC2 instance needs outbound internet access to:
      - Download the GGUF model from Hugging Face
      - Pull Docker images for OpenWebUI
    and inbound access for SSH and the chat interface.
  EOT
  type    = string
  default = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone for the public subnet."
  type        = string
  default     = "us-east-1a"
}

variable "my_ip" {
  description = <<-EOT
    Your local machine's public IP in CIDR notation (e.g. "203.0.113.45/32").
    Used to restrict SSH and Ollama API access to only your machine.
    Find your IP at: https://checkip.amazonaws.com
    The /32 means exactly one IP address.
  EOT
  type    = string
  default = "41.218.155.80/32"   # <-- CHANGE THIS to your IP/32 for better security
                            # e.g. "203.0.113.45/32"
}

variable "instance_type" {
  description = <<-EOT
    EC2 instance type for the model server.
    t3.large
    Recommended by the project resource guide for sub-10B model serving.
    Cost: ~$0.526/hr — remember to stop it when not in use.
  EOT
  type    = string
  default = "t3.large"
}

variable "key_pair_name" {
  description = <<-EOT
    Name of an existing EC2 key pair for SSH access.
    Create one in EC2 Console → Key Pairs → Create key pair.
    Download the .pem file and store it safely.
  EOT
  type    = string
  default = "lab10_key"
}
