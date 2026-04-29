# =============================================================================
# outputs.tf
# CISC 886 — Cloud Computing
# Prints useful values after `terraform apply` so you can immediately SSH in
# and access the web interface without hunting through the AWS Console.
# =============================================================================

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "ID of the EC2 security group"
  value       = aws_security_group.ec2_sg.id
}

output "ec2_public_ip" {
  description = "Public IP address of the EC2 instance — use this for SSH and curl tests"
  value       = aws_instance.infosec_server.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.infosec_server.public_dns
}

output "ssh_command" {
  description = "Ready-to-run SSH command — replace the key path if needed"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.infosec_server.public_ip}"
}

output "openwebui_url" {
  description = "URL to open the chat interface in your browser"
  value       = "http://${aws_instance.infosec_server.public_ip}:3000"
}

output "ollama_api_url" {
  description = "Base URL for the Ollama REST API"
  value       = "http://${aws_instance.infosec_server.public_ip}:11434"
}
