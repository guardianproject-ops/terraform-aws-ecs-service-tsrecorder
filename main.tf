data "aws_region" "this" {}
data "aws_s3_bucket" "this" {
  count  = module.this.enabled ? 1 : 0
  bucket = var.tsrecorder_bucket
}

locals {
  tailscale_environment = [
    {
      name  = "TS_STATE_DIR"
      value = "/var/lib/tailscale"
    },
    {
      name  = "TSRECORDER_HOSTNAME"
      value = var.tsrecorder_hostname
    },
    {
      name  = "TSRECORDER_DST"
      value = "s3://s3.${data.aws_region.this.name}.amazonaws.com"
    },
    {
      name  = "TSRECORDER_BUCKET"
      value = var.tsrecorder_bucket
    },
    {
      name  = "TSRECORDER_UI"
      value = var.tsrecorder_ui_enabled ? "true" : null
    }
  ]
}

module "label_ssm_params_tailscale" {
  source    = "cloudposse/label/null"
  version   = "0.25.0"
  delimiter = "/"
  context   = module.this.context
}

module "label_log_group_tailscale" {
  source     = "cloudposse/label/null"
  version    = "0.25.0"
  delimiter  = "/"
  attributes = ["tailscale"]
  context    = module.this.context
}

resource "aws_cloudwatch_log_group" "tailscale" {
  count             = module.this.enabled ? 1 : 0
  name              = "/${module.label_log_group_tailscale.id}"
  retention_in_days = var.log_group_retention_in_days
  tags              = module.this.tags
}
resource "aws_security_group" "tailscale" {
  count       = module.this.enabled ? 1 : 0
  name        = "${module.this.id}-tsrecorder"
  description = "Security group for tsrecorder"
  vpc_id      = var.vpc_id
  tags        = merge(module.this.tags, { "Name" : "${module.this.id}-tsrecorder" })
}

resource "aws_vpc_security_group_egress_rule" "tailscale_egress_all" {
  count             = module.this.enabled ? 1 : 0
  security_group_id = aws_security_group.tailscale[0].id
  ip_protocol       = "-1" # -1 means all protocols
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all egress traffic"
}

resource "aws_vpc_security_group_ingress_rule" "tailscale_tailscale" {
  count             = module.this.enabled ? 1 : 0
  security_group_id = aws_security_group.tailscale[0].id
  from_port         = 41641
  to_port           = 41641
  ip_protocol       = "udp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all inbound tailscale"
}
resource "aws_security_group" "tailscale_to_efs_state" {
  count       = module.this.enabled ? 1 : 0
  name        = "${module.this.id}-to-efs-state"
  description = "Security group for ECS to EFS access"
  vpc_id      = var.vpc_id
  tags        = merge(module.this.tags, { "Name" : "${module.this.id}-to-efs-state" })
}

resource "aws_vpc_security_group_egress_rule" "tailscale_to_efs_state_egress_all" {
  count             = module.this.enabled ? 1 : 0
  security_group_id = aws_security_group.tailscale_to_efs_state[0].id
  ip_protocol       = "-1" # -1 means all protocols
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all egress traffic"
}

resource "aws_vpc_security_group_ingress_rule" "tailscale_to_efs_state_tailscale" {
  count                        = module.this.enabled ? 1 : 0
  security_group_id            = aws_security_group.tailscale_to_efs_state[0].id
  referenced_security_group_id = aws_security_group.tailscale[0].id
  from_port                    = var.port_efs_tailscale_state
  to_port                      = var.port_efs_tailscale_state
  ip_protocol                  = "tcp"
  description                  = "Allow ECS to access EFS from tailscale"
}

resource "aws_efs_file_system" "tailscale_state" {
  count          = module.this.enabled ? 1 : 0
  creation_token = module.this.id
  encrypted      = true
  kms_key_id     = var.kms_key_arn
  tags           = module.this.tags
}

resource "aws_efs_access_point" "tailscale_state" {
  count          = module.this.enabled ? 1 : 0
  file_system_id = aws_efs_file_system.tailscale_state[0].id
  root_directory {
    path = "/${module.this.id}"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "770"
    }
  }
  posix_user {
    uid = 0
    gid = 0
  }
  tags = module.this.tags
}

resource "aws_efs_mount_target" "tailscale_state" {
  count           = module.this.enabled ? length(var.private_subnet_ids) : 0
  file_system_id  = aws_efs_file_system.tailscale_state[0].id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.tailscale_to_efs_state[0].id]
}

module "tailscale_def" {
  source          = "cloudposse/ecs-container-definition/aws"
  count           = module.this.enabled ? 1 : 0
  version         = "0.61.1"
  container_name  = "tailscale"
  container_image = var.tsrecorder_container_image
  essential       = true

  mount_points = [
    {
      containerPath = "/var/lib/tailscale"
      readOnly      = false
      sourceVolume  = "tailscale-state"
    }
  ]

  secrets = [
    {
      name      = "TS_AUTHKEY",
      valueFrom = "${aws_secretsmanager_secret.authkey[0].arn}:auth_key::"
    },
  ]
  environment      = [for each in local.tailscale_environment : each if each.value != null]
  linux_parameters = { initProcessEnabled = true }
  log_configuration = {
    logDriver = "awslogs"
    options = {
      "awslogs-group"         = aws_cloudwatch_log_group.tailscale[0].name
      "awslogs-region"        = data.aws_region.this.name
      "awslogs-stream-prefix" = "ecs"
    }
    secretOptions = null
  }
}
module "tsrecorder" {
  source                             = "cloudposse/ecs-alb-service-task/aws"
  version                            = "0.76.1"
  context                            = module.this.context
  vpc_id                             = var.vpc_id
  ecs_cluster_arn                    = var.ecs_cluster_arn
  security_group_ids                 = module.this.enabled ? [aws_security_group.tailscale[0].id] : []
  security_group_enabled             = false
  subnet_ids                         = var.public_subnet_ids
  assign_public_ip                   = true
  ignore_changes_task_definition     = false
  exec_enabled                       = var.exec_enabled
  desired_count                      = var.tsrecorder_node_count
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0
  task_cpu                           = var.task_cpu
  task_memory                        = var.task_memory
  container_definition_json = module.this.enabled ? jsonencode(
    concat(
      [module.tailscale_def[0].json_map_object]
    )
  ) : ""

  efs_volumes = module.this.enabled ? [
    {
      host_path = null
      name      = "tailscale-state"
      efs_volume_configuration = [{
        host_path               = null
        file_system_id          = aws_efs_file_system.tailscale_state[0].id
        root_directory          = "/"
        transit_encryption      = "ENABLED"
        transit_encryption_port = var.port_efs_tailscale_state
        authorization_config = [
          {
            access_point_id = aws_efs_access_point.tailscale_state[0].id
            iam             = "DISABLED"
        }]
      }]
    }
  ] : []
}


resource "aws_iam_role_policy_attachment" "tailscale_exec" {
  count      = module.this.enabled ? 1 : 0
  role       = module.tsrecorder.task_exec_role_name
  policy_arn = aws_iam_policy.tailscale_exec[0].arn
}

resource "aws_iam_policy" "tailscale_exec" {
  count  = module.this.enabled ? 1 : 0
  name   = "${module.this.id}-ecs-execution"
  policy = data.aws_iam_policy_document.tailscale_exec[0].json
}

data "aws_iam_policy_document" "tailscale_exec" {
  count = module.this.enabled ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "kms:Decrypt",
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:DescribeMountTargets",
      "elasticfilesystem:DescribeFileSystems"

    ]
    resources = module.this.enabled ? [
      aws_secretsmanager_secret.authkey[0].arn,
      var.kms_key_arn,
      aws_efs_file_system.tailscale_state[0].arn
    ] : []
  }
}

#
resource "aws_iam_role_policy_attachment" "tailscale_task" {
  count      = module.this.enabled ? 1 : 0
  role       = module.tsrecorder.task_role_name
  policy_arn = aws_iam_policy.tailscale_task[0].arn
}

resource "aws_iam_policy" "tailscale_task" {
  count  = module.this.enabled ? 1 : 0
  name   = "${module.this.id}-ecs-task"
  policy = data.aws_iam_policy_document.tailscale_task[0].json
}

data "aws_iam_policy_document" "tailscale_task" {
  count = module.this.enabled ? 1 : 0

  statement {
    sid = "UseKMSKey"
    actions = concat(
      [
        "kms:Encrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      var.tsrecorder_ui_enabled ? [
        "kms:Decrypt",
      ] : []

    )
    resources = [
      var.kms_key_arn
    ]
  }
  statement {
    sid    = "AllowS3RW"
    effect = "Allow"
    actions = concat(
      [
        "s3:PutObject",
        "s3:GetBucketLocation",
      ],
      var.tsrecorder_ui_enabled ? [
        "s3:GetObject",
        "s3:ListBucket"
      ] : []
    )
    resources = module.this.enabled ? [
      data.aws_s3_bucket.this[0].arn,
      var.tsrecorder_bucket_prefix != null ? "${data.aws_s3_bucket.this[0].arn}/${var.tsrecorder_bucket_prefix}/*" : "${data.aws_s3_bucket.this[0].arn}/*"
    ] : []
  }
}
