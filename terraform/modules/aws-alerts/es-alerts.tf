resource "aws_cloudwatch_metric_alarm" "es-cluster-status-yellow-warning" {
  for_each = var.aws_es_clusters
  alarm_name        = "es-${each.key}-status-yellow-warning"
  alarm_description = "Average elasticsearch cluster is in yellow warning state for past 15 minutes"
  namespace         = "AWS/ES"
  metric_name       = "ClusterStatus.yellow"
  dimensions = {
    ClientId            = var.aws_account_id
    DomainName          = each.key
  }
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Maximum"
  period              = "300"
  evaluation_periods  = "3"
  threshold           = "1"
  alarm_actions       = [var.aws_slack_sns_topic_arn]
  ok_actions          = [var.aws_slack_sns_topic_arn]
  treat_missing_data  = "breaching"
}

resource "aws_cloudwatch_metric_alarm" "es-cluster-status-red-critical" {
  for_each = var.aws_es_clusters
  alarm_name        = "es-${each.key}-status-red-critical"
  alarm_description = "Average elasticsearch cluster is in red critical state for past 15 minutes"
  namespace         = "AWS/ES"
  metric_name       = "ClusterStatus.red"
  dimensions = {
    ClientId            = var.aws_account_id
    DomainName          = each.key
  }
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Maximum"
  period              = "300"
  evaluation_periods  = "3"
  threshold           = "1"
  alarm_actions       = [var.aws_slack_sns_topic_arn]
  ok_actions          = [var.aws_slack_sns_topic_arn]
  treat_missing_data  = "breaching"
}

resource "aws_cloudwatch_metric_alarm" "es-insufficient-available-nodes-warning" {
  for_each = var.aws_es_clusters
  alarm_name          = "es-${each.key}-insufficient-available-nodes-warning"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "Nodes"
  dimensions = {
    ClientId            = var.aws_account_id
    DomainName          = each.key
  }
  namespace           = "AWS/ES"
  period              = "300"
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Available ES Nodes are low for past 15 minutes"
  alarm_actions       = [var.aws_slack_sns_topic_arn]
  ok_actions          = [var.aws_slack_sns_topic_arn]
  treat_missing_data  = "breaching"
}  

resource "aws_cloudwatch_metric_alarm" "es-cpu-utilization-critical" {
  for_each = var.aws_es_clusters
  alarm_name          = "es-${each.key}-cpu-utilization-critical"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  dimensions = {
    ClientId            = var.aws_account_id
    DomainName          = each.key
  }
  namespace           = "AWS/ES"
  period              = "300"
  statistic           = "Average"
  threshold           = "90"
  alarm_description   = "ES CPU utilization is over 90% for past 15 minutes"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.aws_slack_sns_topic_arn]
  ok_actions          = [var.aws_slack_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "es-free-storage-space-critical" {
  for_each = var.aws_es_clusters
  alarm_name          = "es-${each.key}-freestoragespace-critical"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "FreeStorageSpace"
  dimensions = {
    ClientId            = var.aws_account_id
    DomainName          = each.key
  }
  namespace           = "AWS/ES"
  period              = "300"
  statistic           = "Average"
  threshold           = "10000"
  alarm_description   = "ES free storage space is extremely low for past 15 minutes"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.aws_slack_sns_topic_arn]
  ok_actions          = [var.aws_slack_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "es-free-storage-space-warning" {
  for_each = var.aws_es_clusters
  alarm_name          = "es-${each.key}-freestoragespace-warning"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "FreeStorageSpace"
  dimensions = {
    ClientId            = var.aws_account_id
    DomainName          = each.key
  }
  namespace           = "AWS/ES"
  period              = "300"
  statistic           = "Average"
  threshold           = "50000"
  alarm_description   = "ES free storage space is low past 15 minutes"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.aws_slack_sns_topic_arn]
  ok_actions          = [var.aws_slack_sns_topic_arn]
}