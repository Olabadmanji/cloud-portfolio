terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-2"
}

variable "alert_email" {
  description = "Email address for SNS real-time notifications"
  type        = string
}

# 1. S3 Bucket with EventBridge Enabled
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "ingest_bucket" {
  bucket = "ob-eda-ingest-bucket-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket      = aws_s3_bucket.ingest_bucket.id
  eventbridge = true
}

# 2. DynamoDB Table (On-Demand)
resource "aws_dynamodb_table" "processing_records" {
  name         = "EventProcessingRecords"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "RecordId"

  attribute {
    name = "RecordId"
    type = "S"
  }
}

# 3. SNS Topic & Email Subscription
resource "aws_sns_topic" "alerts_topic" {
  name = "eda-processing-alerts"
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.alerts_topic.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# 4. IAM Role & Least-Privilege Policy for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "eda-lambda-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "eda-least-privilege-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.ingest_bucket.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.processing_records.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts_topic.arn
      }
    ]
  })
}

# 5. Lambda Function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "eda-s3-event-processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 15
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.processing_records.name
      SNS_TOPIC_ARN  = aws_sns_topic.alerts_topic.arn
    }
  }
}

# 6. EventBridge Rule & Lambda Target
resource "aws_cloudwatch_event_rule" "s3_upload_rule" {
  name        = "s3-upload-to-lambda-rule"
  description = "Routes S3 Object Created events asynchronously to the Lambda processor"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.ingest_bucket.id]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.s3_upload_rule.name
  target_id = "ProcessS3Uploads"
  arn       = aws_lambda_function.processor.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_upload_rule.arn
}

# 7. Outputs
output "ingest_bucket_name" {
  description = "Upload test files to this S3 bucket to trigger the pipeline"
  value       = aws_s3_bucket.ingest_bucket.id
}

output "lambda_function_name" {
  description = "Deployed Lambda processor function name"
  value       = aws_lambda_function.processor.function_name
}