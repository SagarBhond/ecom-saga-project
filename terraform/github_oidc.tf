# ============================================================
# GITHUB ACTIONS OIDC PROVIDER
#
# Registers GitHub's OIDC issuer as a trusted identity provider
# in this AWS account so workflows can assume roles without
# long-lived AWS access keys.
#
# NOTE: If a provider for token.actions.githubusercontent.com
# already exists in this account (e.g. created manually via
# the console), importing it is required before apply:
#
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::882040517001:oidc-provider/token.actions.githubusercontent.com
#
# Otherwise "apply" will fail with "already exists".
# ============================================================

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.github.certificates[0].sha1_fingerprint
  ]

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# GITHUB ACTIONS DEPLOY ROLE
#
# Assumed by the "deploy" job in ci-cd-pipeline.yml via OIDC.
# That job uses `environment: production`, which means GitHub
# issues the token with:
#
#   sub = repo:<org>/<repo>:environment:production
#
# NOT repo:<org>/<repo>:ref:refs/heads/main — using the ref
# form here will always fail with
# "Not authorized to perform sts:AssumeRoleWithWebIdentity"
# because the claim GitHub actually sends never matches it.
# ============================================================

resource "aws_iam_role" "github_actions_deploy" {
  name = "${var.project_name}-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:environment:production"
          }
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# DEPLOY ROLE PERMISSIONS
#
# Matches exactly what the "deploy" job in ci-cd-pipeline.yml
# calls: EC2 describe (find the instance) and SSM send-command
# / get-command-invocation (run the deployment script).
# ============================================================

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "${var.project_name}-github-actions-deploy-policy"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "EC2Describe"
        Effect = "Allow"

        Action = [
          "ec2:DescribeInstances"
        ]

        Resource = "*"
      },
      {
        Sid    = "SSMDeploy"
        Effect = "Allow"

        Action = [
          "ssm:DescribeInstanceInformation",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]

        Resource = "*"
      }
    ]
  })
}
