output "role_arn" {
  description = "Terraform 実行用のロール ARN"
  value       = aws_iam_role.terraform_role.arn
}
