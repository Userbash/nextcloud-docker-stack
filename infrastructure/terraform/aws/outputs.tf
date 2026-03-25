output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.nextcloud.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.nextcloud.zone_id
}

output "rds_endpoint" {
  description = "RDS cluster endpoint"
  value       = aws_rds_cluster.nextcloud.endpoint
  sensitive   = true
}

output "rds_reader_endpoint" {
  description = "RDS cluster reader endpoint"
  value       = aws_rds_cluster.nextcloud.reader_endpoint
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.nextcloud.id
}

output "security_group_alb" {
  description = "Security group ID for ALB"
  value       = aws_security_group.nextcloud_alb.id
}

output "security_group_app" {
  description = "Security group ID for application"
  value       = aws_security_group.nextcloud_app.id
}

output "security_group_db" {
  description = "Security group ID for database"
  value       = aws_security_group.nextcloud_db.id
}

output "instance_ips" {
  description = "Private IPs of EC2 instances"
  value       = aws_instance.nextcloud[*].private_ip
}

output "instance_public_ips" {
  description = "Public IPs of EC2 instances"
  value       = aws_instance.nextcloud[*].public_ip
}

output "secrets_manager_arn" {
  description = "ARN of Secrets Manager secret"
  value       = aws_secretsmanager_secret.nextcloud_db.arn
}

output "kms_key_id" {
  description = "KMS key ID for RDS encryption"
  value       = aws_kms_key.rds.id
}

output "deployment_info" {
  description = "Deployment information"
  value = {
    environment    = var.environment
    region         = var.aws_region
    vpc_cidr       = var.vpc_cidr
    instance_count = var.instance_count
    instance_type  = var.instance_type
  }
}

output "nextcloud_url" {
  description = "URL to access Nextcloud"
  value       = "https://${var.domain_name}"
}
