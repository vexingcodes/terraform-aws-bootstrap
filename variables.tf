variable "iam_group" {
  type        = string
  default     = "terraform"
  description = "The name of the IAM group Terraform will use."
}

variable "iam_user" {
  type        = string
  default     = "terraform"
  description = "The name of the IAM user Terraform will use."
}

variable "secret" {
  type        = string
  default     = "terraform"
  description = "The name of the Amazon Secrets Manager secret that will contain the provider/backend variables needed to use Terraform."
}

variable "dynamodb" {
  type        = string
  default     = "terraform"
  description = "The name of the DynamoDB that will be used to lock Terraform state files to prevent concurrent access."
}

variable "s3_bucket" {
  type        = string
  description = "The name of the S3 bucket that will contain the Terraform state files. This name must be globally unique across all of AWS."
}
