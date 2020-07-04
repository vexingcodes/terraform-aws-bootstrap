output "secret_arn" {
  value       = aws_secretsmanager_secret.terraform.arn
  description = "The ARN of the Amazon Secrets Manager secret containing the provider/backend Terraform variables. This ARN can be used to grant IAM users read access to the secret so that they can use Terraform."
}
