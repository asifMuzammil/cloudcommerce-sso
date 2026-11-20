# ---------------------------------------------------------------------------
# AWS integrations for the ForgeRock stack on the dev box:
#   1. CloudWatch Logs  - AM's stdout (incl. audit events: logins, MFA) is
#                         shipped by Docker's awslogs driver.
#   2. SSM Parameter Store - runtime secrets (SecureString) under
#                         /cloudcommerce/forgerock/*, so they live outside git
#                         and survive `terraform destroy` of the instance.
# The instance role gets exactly these permissions and nothing more.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  ssm_prefix = "/cloudcommerce/forgerock"
}

resource "aws_cloudwatch_log_group" "am" {
  name              = "/cloudcommerce/forgerock/am"
  retention_in_days = 7 # dev data: keep a week, then let AWS delete it (cost)
}

resource "aws_iam_role_policy" "devbox_runtime" {
  name = "cloudcommerce-devbox-runtime"
  role = aws_iam_role.devbox.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ShipAmLogsToCloudWatch"
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = [
          aws_cloudwatch_log_group.am.arn,
          "${aws_cloudwatch_log_group.am.arn}:log-stream:*",
        ]
      },
      {
        # SecureString with the AWS-managed aws/ssm key: its key policy already
        # allows decryption through SSM for principals in this account.
        Sid    = "ForgeRockSecretsInParameterStore"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParametersByPath", "ssm:PutParameter"]
        Resource = [
          "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}",
          "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*",
        ]
      },
    ]
  })
}

output "am_log_group" {
  value = aws_cloudwatch_log_group.am.name
}

output "ssm_prefix" {
  value = local.ssm_prefix
}
