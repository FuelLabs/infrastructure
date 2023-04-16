# AWS
variable "aws_account_id" {
  type = string
}

variable "aws_region" {
  type = string
}

# Opensearch
variable "aws_es_clusters" {
  type    = map
}

# SNS
variable "aws_slack_sns_topic_arn" {
  type = string
}

module "aws-infra-alerts" {
  source = "../../modules/aws-alerts"

  # AWS
  aws_region                      = var.aws_region
  aws_account_id                  = var.aws_account_id

  aws_slack_sns_topic_arn         = var.aws_slack_sns_topic_arn

  aws_es_clusters                 = var.aws_es_clusters 
}

