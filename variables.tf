variable "vpc_id" {
  type        = string
  description = "The VPC that the ECS cluster is in"
}

variable "kms_key_arn" {
  type        = string
  description = "Used for transit and tailscale state encryption"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = <<EOT
The ids for the private subnets that EFS will be deployed into
EOT
}

variable "tsrecorder_ui_enabled" {
  type        = bool
  default     = true
  description = <<EOT
Whether or not to enable the recorder ui.
EOT
}

variable "tsrecorder_bucket" {
  type        = string
  description = <<EOT
The S3 bucket name, in this region, to put ssh session recordings.
EOT
}

variable "tsrecorder_bucket_prefix" {
  type        = string
  default     = null
  description = <<EOT
The prefix the tsrecorder will use.
EOT
}

variable "tsrecorder_container_image" {
  type        = string
  default     = "docker.io/tailscale/tsrecorder:stable"
  description = <<EOT
The fully qualified container image for tsrecorder.
EOT
}

variable "port_efs_tailscale_state" {
  type        = number
  default     = 2049
  description = <<EOT
The port number at which the tailscale state efs mount is available
EOT
}

variable "tailscale_tags" {
  type = list(string)

  description = "The list of tags that will be assigned to tailscale node created by this stack."
  validation {
    condition = alltrue([
      for tag in var.tailscale_tags : can(regex("^tag:", tag))
    ])
    error_message = "max_allocated_storage: Each tag in tailscale_tags must start with 'tag:'"
  }
}


variable "tailscale_tailnet" {
  type = string

  description = <<EOT
  description = The tailnet domain (or "organization's domain") for your tailscale tailnet, this s found under Settings > General > Organization
EOT
}

variable "tailscale_client_id" {
  type        = string
  sensitive   = true
  description = "The OIDC client id for tailscale that has permissions to create auth keys with the `tailscale_tags` tags"
}

variable "tailscale_client_secret" {
  type        = string
  sensitive   = true
  description = "The OIDC client secret paired with `tailscale_client_id`"
}

variable "exec_enabled" {
  type        = bool
  description = "Specifies whether to enable Amazon ECS Exec for the tasks within the service"
  default     = false
}

variable "public_subnet_ids" {
  type        = list(string)
  description = <<EOT
The ids for the public subnets that ECS will be deployed into
EOT
}

variable "ecs_cluster_arn" {
  type        = string
  description = "The ECS cluster ARN this service will be deployed in"
}

variable "tsrecorder_hostname" {
  type        = string
  default     = null
  description = <<EOT
The hostname for this tailscale device, will default to to the context id
EOT
}

variable "tsrecorder_node_count" {
  type        = number
  default     = 1
  description = <<EOT
The number of instances to run in this service.
EOT
}

variable "log_group_retention_in_days" {
  default     = 30
  type        = number
  description = <<EOT
The number in days that cloudwatch logs will be retained.
EOT
}

variable "task_cpu" {
  type        = number
  description = "The number of CPU units used by the task. If using `FARGATE` launch type `task_cpu` must match supported memory values (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size)"
}

variable "task_memory" {
  type        = number
  description = "The amount of memory (in MiB) used by the task. If using Fargate launch type `task_memory` must match supported cpu value (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size)"
}
