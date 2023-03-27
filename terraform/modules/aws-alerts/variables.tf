variable "aws_account_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_slack_sns_topic_arn" {
  type = string
}

variable "aws_es_clusters" {
  type    = map
}
