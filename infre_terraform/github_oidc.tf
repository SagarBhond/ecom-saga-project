# GitHub Actions OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "ab9d0263244dd0326eb67015705a667e79cfe998"
  ]

  tags = {
    Project = "instance-ecom-saga"
  }
}

# GitHub Actions deployment role
resource "aws_iam_role" "github_actions_deploy" {
  name = "instance-ecom-saga-github-actions-deploy"

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
          }

          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:SagarBhond/ecom-saga-project:*"
          }
        }
      }
    ]
  })

  tags = {
    Project = "instance-ecom-saga"
  }
}

resource "aws_iam_role_policy" "github_actions_deploy_policy" {
  name = "instance-ecom-saga-github-actions-deploy-policy"
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
