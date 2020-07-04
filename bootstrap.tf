data "aws_region" "current" {}

resource "aws_iam_group" "terraform" {
  name = var.iam_group
}

resource "aws_iam_group_policy_attachment" "terraform" {
  group      = aws_iam_group.terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user" "terraform" {
  name          = var.iam_user
  force_destroy = true
  depends_on    = [aws_iam_group.terraform]
}

resource "aws_iam_access_key" "terraform" {
  user = aws_iam_user.terraform.name
}

resource "aws_iam_user_group_membership" "terraform" {
  user   = aws_iam_user.terraform.name
  groups = [aws_iam_group.terraform.name]
}

resource "aws_s3_bucket" "terraform" {
  bucket        = var.s3_bucket
  acl           = "private"
  force_destroy = true
  versioning {
    enabled = true
  }
}

resource "aws_dynamodb_table" "terraform" {
  name = var.dynamodb

  read_capacity  = 1
  write_capacity = 1
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

resource "aws_secretsmanager_secret" "terraform" {
  name        = var.secret
  description = "Terraform configuration values for remote state storage."
}

resource "aws_secretsmanager_secret_version" "terraform" {
  secret_id     = aws_secretsmanager_secret.terraform.id
  secret_string = jsonencode({
    bucket     = aws_s3_bucket.terraform.id
    lock_table = aws_dynamodb_table.terraform.id
    region     = data.aws_region.current.name
    user       = aws_iam_user.terraform.name
    access_key = aws_iam_access_key.terraform.id
    secret_key = aws_iam_access_key.terraform.secret
  })
}
