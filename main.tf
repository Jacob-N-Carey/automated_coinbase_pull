terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "bpi-price-bucket" {
  bucket = "bpi-price-bucket-00001"
  acl           = "private"
}

resource "aws_iam_policy" "coinbase_lambda_iam_policy" {
  name        = "coinbase_lambda_iam_policy"
  path        = "/"
  description = "Policy for Coinbase Lambda to PutObject in s3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:GetObjectAcl",
          "s3:DeleteObject",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "coinbase_lambda_iam_role" {
  name = "coinbase_lambda_iam_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "coinbase_lambda_role_policy_attach" {
  role       = aws_iam_role.coinbase_lambda_iam_role.name
  policy_arn = aws_iam_policy.coinbase_lambda_iam_policy.arn
}

data "archive_file" "default" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "${path.module}/lambda_zip/lambda.zip"
}

resource "aws_lambda_function" "coinbase_lambda" {
  filename         = "${path.module}/lambda_zip/lambda.zip"
  function_name    = "coinbase_api_lambda_function"
  role             = aws_iam_role.coinbase_lambda_iam_role.arn
  handler          = "coinbase_lambda.handler"
  runtime          = "python3.8"
  depends_on       = [aws_iam_role_policy_attachment.coinbase_lambda_role_policy_attach]
  source_code_hash = filebase64sha256("${path.module}/lambda_zip/lambda.zip")
}

resource "aws_cloudwatch_event_rule" "every_five_minutes" {
  name                = "every-five-minutes"
  description         = "Fires every five minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "call_coinbase_lambda_every_five_minutes" {
  rule = aws_cloudwatch_event_rule.every_five_minutes.name
  arn = aws_lambda_function.coinbase_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_coinbase_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.coinbase_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_five_minutes.arn
}