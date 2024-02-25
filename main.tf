terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_sns_topic" "incoming" {
  name = coalesce(var.sns_topic_name, "${var.service_name}-topic")
}

resource "aws_s3_bucket" "incoming_bucket" {
  # Use terraform import
}

resource "aws_s3_bucket" "destination_bucket" {
  # Use terraform import
}

resource "aws_dynamodb_table" "senders_table" {
  name           = coalesce(var.senders_dynamo_table_name, "${var.service_name}-allowed_senders")
  billing_mode   = "PROVISIONED"
  read_capacity  = 10
  write_capacity = 10
  hash_key       = "sender"

  attribute {
    name = "sender"
    type = "S"
  }

  # attribute {
  #   name = "allow"
  #   type = "B"
  # }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.service_name}_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "lambda_extract_attachments" {
  type = "zip"

  source_file = "src/extract_attachments.py"
  output_path = "dist/extract_attachments.zip"
}

data "archive_file" "lambda_filter_incoming_email" {
  type = "zip"

  source_file = "src/filter_incoming_email.py"
  output_path = "dist/filter_incoming_email.zip"
}

resource "aws_lambda_function" "filter_incoming_email" {
  function_name = "${var.service_name}-filter_incoming_email"
  runtime = "python3.9"
  handler = "filter_incoming_email.lambda_handler"

  role = aws_iam_role.lambda_exec.arn
  
  filename = data.archive_file.lambda_filter_incoming_email.output_path
  source_code_hash = data.archive_file.lambda_filter_incoming_email.output_base64sha256

  environment {
    variables = {
      DDB_TABLE_NAME = aws_dynamodb_table.senders_table.name
    }
  }
}

resource "aws_lambda_function" "extract_attachments" {
  function_name = "${var.service_name}-extract_attachments"
  runtime = "python3.9"
  handler = "extract_attachments.lambda_handler"
  
  role = aws_iam_role.lambda_exec.arn
  
  filename = data.archive_file.lambda_extract_attachments.output_path
  source_code_hash = data.archive_file.lambda_extract_attachments.output_base64sha256

  environment {
    variables = {
      SRC_BUCKET = aws_s3_bucket.incoming_bucket.bucket
      SRC_PREFIX = var.incoming_bucket_prefix
      DEST_BUCKET = aws_s3_bucket.destination_bucket.bucket
      DEST_PREFIX = var.destination_bucket_prefix
    }
  }
}

resource "aws_sns_topic_subscription" "extract_attachments" {
  topic_arn = aws_sns_topic.incoming.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.extract_attachments.arn
}

resource "aws_s3_bucket_policy" "allow_ses_write_to_s3" {
  bucket = aws_s3_bucket.incoming_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "s3:PutObject"
      Effect = "Allow"
      Sid    = "AllowSESPuts"
      Resource = "${aws_s3_bucket.incoming_bucket.arn}/${var.incoming_bucket_prefix}*"
      Principal = {
        Service = "ses.amazonaws.com"
      }
    }]
  })
}

resource "aws_lambda_permission" "allow_ses" {
  statement_id   = "AllowExecutionFromSES"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.filter_incoming_email.function_name
  # source_account = "${data.aws_caller_identity.current.account_id}"
  principal      = "ses.amazonaws.com"
}

resource "aws_ses_receipt_rule_set" "incoming" {
  rule_set_name = "${var.service_name}-rules"
}

resource "aws_ses_receipt_rule" "filter_and_store" {
  name          = "filter_and_store"
  rule_set_name = aws_ses_receipt_rule_set.incoming.rule_set_name
  recipients    = var.recipients
  enabled       = true
  scan_enabled  = true

  lambda_action {
    position    = 1
    invocation_type = "RequestResponse"
    function_arn = aws_lambda_function.filter_incoming_email.arn
    topic_arn   = aws_sns_topic.incoming.arn
  }

  s3_action {
    position    = 2
    bucket_name = aws_s3_bucket.incoming_bucket.bucket
    object_key_prefix = var.incoming_bucket_prefix
    topic_arn   = aws_sns_topic.incoming.arn
  }

  depends_on    = [
    aws_sns_topic.incoming,
    aws_s3_bucket.incoming_bucket,
    aws_lambda_function.filter_incoming_email,
  ]
}