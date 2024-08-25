terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.56.1"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Terraform = "true"
    }
  }
}

# TLS 証明書を取得するためのデータソースを定義
data "tls_certificate" "terraform_cloud" {
  url = "https://${var.terraform_cloud_host}"
}

# Terraform Cloud 用の OpenID Connect プロバイダを定義
resource "aws_iam_openid_connect_provider" "terraform_cloud" {
  url = data.tls_certificate.terraform_cloud.url
  # OpenID Connect audience
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = [data.tls_certificate.terraform_cloud.certificates[0].sha1_fingerprint]
}

# 信頼ポリシー
data "aws_iam_policy_document" "terraform_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.terraform_cloud.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${var.terraform_cloud_host}:aud"

      values = [
        # OpenID Connect audience
        one(aws_iam_openid_connect_provider.terraform_cloud.client_id_list)
      ]
    }

    condition {
      test     = "StringLike"
      variable = "${var.terraform_cloud_host}:sub"

      values = [
        "organization:${var.terraform_cloud_organization}:project:*:workspace:*:run_phase:*"
      ]
    }
  }
}

resource "aws_iam_role" "terraform_role" {
  name               = "terraform-role"
  assume_role_policy = data.aws_iam_policy_document.terraform_assume_role_policy.json
}

# Terraform Cloud を介して AWS リソースを管理するためのポリシーになります。
# 用途によっては、より制限の厳しいポリシーを適用してください。
data "aws_iam_policy_document" "terraform_policy" {
  statement {
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_policy" {
  name        = "terraform-policy"
  description = "Policy for Terraform Cloud"
  policy      = data.aws_iam_policy_document.terraform_policy.json
}

resource "aws_iam_role_policy_attachment" "terraform_policy_attachment" {
  role       = aws_iam_role.terraform_role.name
  policy_arn = aws_iam_policy.terraform_policy.arn
}
