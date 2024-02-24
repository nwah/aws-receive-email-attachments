variable "aws_region" {
  description = "AWS region for all resources."
  
  type    = string
  default = "us-east-2"
}

variable "service_name" {
  description = "Name of the service/app. Used as a prefix in resource names."

  type    = string
}

variable "senders_dynamo_table_name" {
  description = "Name of the DynamoDB table used to look up allowed senders"

  type    = string
  # default = "${service_name}-allowed_senders"
  nullable = true
}

variable "incoming_bucket_name" {
  description = "Name of the S3 bucket used to store raw emails."

  type    = string
  # default = "${service_name}-email_attachments"
  nullable = true
}

variable "incoming_bucket_prefix" {
  description = "S3 prefix where raw emails should be stored."

  type    = string
  default = "incoming"
}

variable "destination_bucket_name" {
  description = "Name of the S3 bucket used to store raw emails."

  type    = string
  # default = var.incoming_bucket_name
  nullable = true
}

variable "destination_bucket_prefix" {
  description = "S3 prefix where extracted attachments should be stored."

  type    = string
  default = "attachments"
}

variable "recipients" {
  description = "Receiving email address(es) that this flow should be triggered for."

  type    = list(string)
}

variable "sns_topic_name" {
  description = "SNS topic name for notifications when email is received or processed"

  type    = string
  # default = "${service_name}-topic"
  nullable = true
}