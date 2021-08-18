# initializes terraform 
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# sets up aws as the provider we are going to be using
provider "aws" {
  region = "us-east-1"
}

# creates the s3 bucket for us to load our json into 
resource "aws_s3_bucket" "bpi-price-bucket" {
  bucket = "bpi-price-bucket-00001"
  acl           = "private"
}

# creates the iam policy for the coinbase lambda with the required permissions 
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

# creates the iam role for the lambda 
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

# attaches the iam role policy 
resource "aws_iam_role_policy_attachment" "coinbase_lambda_role_policy_attach" {
  role       = aws_iam_role.coinbase_lambda_iam_role.name
  policy_arn = aws_iam_policy.coinbase_lambda_iam_policy.arn
}

# creates a zip file of the coinbase_lambda.py to load to lambda 
data "archive_file" "default" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "${path.module}/lambda_zip/lambda.zip"
}

# creates the lambda 
resource "aws_lambda_function" "coinbase_lambda" {
  filename         = "${path.module}/lambda_zip/lambda.zip"
  function_name    = "coinbase_api_lambda_function"
  role             = aws_iam_role.coinbase_lambda_iam_role.arn
  handler          = "coinbase_lambda.handler"
  runtime          = "python3.8"
  depends_on       = [aws_iam_role_policy_attachment.coinbase_lambda_role_policy_attach]
  source_code_hash = filebase64sha256("${path.module}/lambda_zip/lambda.zip")
}

# sets up the cloudwatch rule to trigger the lambda every five minutes 
resource "aws_cloudwatch_event_rule" "every_five_minutes" {
  name                = "every-five-minutes"
  description         = "Fires every five minutes"
  schedule_expression = "rate(5 minutes)"
}

# attaches the cloudwatch trigger to the lambda 
resource "aws_cloudwatch_event_target" "call_coinbase_lambda_every_five_minutes" {
  rule = aws_cloudwatch_event_rule.every_five_minutes.name
  arn = aws_lambda_function.coinbase_lambda.arn
}

# allows cloudwatch and lambda to interact
resource "aws_lambda_permission" "allow_cloudwatch_to_call_coinbase_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.coinbase_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_five_minutes.arn
}