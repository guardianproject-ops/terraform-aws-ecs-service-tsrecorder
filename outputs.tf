output "security_group_id" {
  value = try(aws_security_group.tailscale[0].id, "")
}
output "efs_security_group_id" {
  value = try(aws_security_group.tailscale_to_efs_state[0].id, "")
}
output "efs_file_system_id" {
  value = try(aws_efs_file_system.tailscale_state[0].id, "")
}
output "cloudwatch_log_group_tailscale" {
  description = "All outputs from `aws_cloudwatch_log_group.tailscale`"
  value       = try(aws_cloudwatch_log_group.tailscale[0].arn, "")
}

output "cloudwatch_log_group_arn_tailscale" {
  description = "Cloudwatch log group ARN for tailscale"
  value       = try(aws_cloudwatch_log_group.tailscale[0].arn, "")
}

output "cloudwatch_log_group_name_tailscale" {
  description = "Cloudwatch log group name for tailscale"
  value       = try(aws_cloudwatch_log_group.tailscale[0].name, "")
}

output "secrets_manager_secret_authkey_arn" {
  value = try(aws_secretsmanager_secret.authkey[0].arn, "")
}

output "secrets_manager_secret_authkey_id" {
  value = try(aws_secretsmanager_secret.authkey[0].id, "")
}
