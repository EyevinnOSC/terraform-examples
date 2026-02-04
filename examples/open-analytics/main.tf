terraform {
  required_version = ">= 1.6.0" # Compatible with Terraform >= 1.6.0 and OpenTofu >= 1.6.0
  required_providers {
    osc = {
      source = "registry.terraform.io/EyevinnOSC/osc"
      #source = "local/eyevinnosc/osc" 
      version = "0.4.0"
    }
  }
}
############################
# Provider
############################
provider "osc" {
  pat         = var.osc_pat
  environment = var.osc_environment
}


############################
# Variables 
############################

## --- General ---

# Your OSC Personal Access Token (PAT). Sensitive
variable "osc_pat" {
  type        = string
  sensitive   = true
  description = "Eyevinn OSC Personal Access Token"
}

# Environment prod|stage|dev
variable "osc_environment" {
  type        = string
  default     = "prod"
  description = "OSC Environment"
}

variable "analyticspeline_name" {
  type        = string
  default     = "myopenanalytics"
  description = "Name of the analytics pipeline. Lower case letters and numbers only"
}


## --- SmoothMQ ---
variable "smoothmqaccesskey" {
  type        = string
  sensitive   = true
  description = "Set the SmoothMQ Access Key"
}
variable "smoothmqsecretkey" {
  type        = string
  sensitive   = true
  description = "Set the SmoothMQ Secret Key"
}

## --- ClickHouse Server ---
variable "clickhouseusername" {
  type        = string
  sensitive   = true
  description = "Set the ClickHouse Server Username"
}
variable "clickhousepassword" {
  type        = string
  sensitive   = true
  description = "Set the Clickhouse Server Password"
}

## --- Grafana ---
variable "grafanadashboardurl" {
  type        = string
  default     = "https://raw.githubusercontent.com/EyevinnOSC/terraform-examples/refs/heads/main/examples/open-analytics/grafana-dashboards/open-analytics-example-dashboard.json"
  description = "Url to Grafana dashboard JSON to be installed"
}

############################
# Resource: Secrets
############################

resource "osc_secret" "smoothmqaccesskey" {
  service_ids  = ["poundifdef-smoothmq", "eyevinn-player-analytics-eventsink", "eyevinn-player-analytics-worker"]
  secret_name  = "${var.analyticspeline_name}smoothmqaccesskey"
  secret_value = var.smoothmqaccesskey
}
resource "osc_secret" "smoothmqsecretkey" {
  service_ids  = ["poundifdef-smoothmq", "eyevinn-player-analytics-eventsink", "eyevinn-player-analytics-worker"]
  secret_name  = "${var.analyticspeline_name}smoothmqsecretkey"
  secret_value = var.smoothmqsecretkey
}
resource "osc_secret" "clickhouseusername" {
  service_ids  = ["clickhouse-clickhouse", "eyevinn-player-analytics-worker", "grafana-grafana"]
  secret_name  = "${var.analyticspeline_name}clickhouseusername"
  secret_value = var.clickhouseusername
}
resource "osc_secret" "clickhousepassword" {
  service_ids  = ["clickhouse-clickhouse", "eyevinn-player-analytics-worker", "grafana-grafana"]
  secret_name  = "${var.analyticspeline_name}clickhousepassword"
  secret_value = var.clickhousepassword
}
resource "osc_secret" "clickhouseurl" {
  service_ids  = ["eyevinn-player-analytics-worker"]
  secret_name  = "${var.analyticspeline_name}clickhouseconstructedurl"
  secret_value = "https://${var.clickhouseusername}:${var.clickhousepassword}@${local.clickhouse_host}"
}


############################
# null_resources (scripts)
############################

## polling for Smooth MQ instance to be ready and creates a queue
resource "null_resource" "create_queue" {
  provisioner "local-exec" {
    environment = {
      AWS_ACCESS_KEY_ID     = var.smoothmqaccesskey
      AWS_SECRET_ACCESS_KEY = var.smoothmqsecretkey
    }
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      bash ${path.module}/scripts/create_queue.sh \
      ${osc_poundifdef_smoothmq.smooth_mq_instance.instance_url} \
      ${osc_poundifdef_smoothmq.smooth_mq_instance.name}
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ${path.module}/queue_output.json"
  }
}

############################
# Storage
############################
# Read the queue URL from file if it exists, otherwise return empty (for destroy operations)
# Using external data source instead of local_file to handle missing file gracefully
data "external" "queue_info" {
  program = ["bash", "-c", "if [ -f '${path.module}/queue_output.json' ]; then cat '${path.module}/queue_output.json'; else echo '{\"QueueUrl\": \"\"}'; fi"]

  depends_on = [null_resource.create_queue]
}
locals {
  queue_url       = data.external.queue_info.result.QueueUrl
  clickhouse_host = replace(osc_clickhouse_clickhouse.clickhouse_instance.instance_url, "https://", "")
}


## polling waiting for queue to be ready
resource "null_resource" "wait_for_queue" {
  depends_on = [data.external.queue_info]
  provisioner "local-exec" {
    environment = {
      AWS_ACCESS_KEY_ID     = var.smoothmqaccesskey
      AWS_SECRET_ACCESS_KEY = var.smoothmqsecretkey
    }
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      bash ${path.module}/scripts/wait_for_queue.sh \
        ${local.queue_url} \
        ${osc_poundifdef_smoothmq.smooth_mq_instance.instance_url}
    EOT
  }
}

############################
# Services
############################

resource "osc_poundifdef_smoothmq" "smooth_mq_instance" {
  name       = var.analyticspeline_name
  access_key = format("{{secrets.%s}}", osc_secret.smoothmqaccesskey.secret_name)
  secret_key = format("{{secrets.%s}}", osc_secret.smoothmqsecretkey.secret_name)
}
resource "osc_eyevinn_player_analytics_eventsink" "eventsink_instance" {
  name                  = var.analyticspeline_name
  aws_access_key_id     = format("{{secrets.%s}}", osc_secret.smoothmqaccesskey.secret_name)
  aws_secret_access_key = format("{{secrets.%s}}", osc_secret.smoothmqsecretkey.secret_name)
  sqs_queue_url         = local.queue_url
  sqs_endpoint          = osc_poundifdef_smoothmq.smooth_mq_instance.instance_url
}
resource "osc_clickhouse_clickhouse" "clickhouse_instance" {
  name     = var.analyticspeline_name
  user     = format("{{secrets.%s}}", osc_secret.clickhouseusername.secret_name)
  password = format("{{secrets.%s}}", osc_secret.clickhousepassword.secret_name)
}
resource "osc_eyevinn_player_analytics_worker" "worker_instance" {
  name                  = var.analyticspeline_name
  click_house_url       = format("{{secrets.%s}}", osc_secret.clickhouseurl.secret_name)
  sqs_queue_url         = local.queue_url
  aws_access_key_id     = format("{{secrets.%s}}", osc_secret.smoothmqaccesskey.secret_name)
  aws_secret_access_key = format("{{secrets.%s}}", osc_secret.smoothmqsecretkey.secret_name)
  sqs_endpoint          = osc_poundifdef_smoothmq.smooth_mq_instance.instance_url
}


resource "osc_secret" "grafanadatasource" {
  service_ids  = ["grafana-grafana"]
  secret_name  = "${var.analyticspeline_name}grafanadatasources"
  secret_value = "ClickHouse:vertamedia-clickhouse-datasource:${osc_clickhouse_clickhouse.clickhouse_instance.instance_url};${var.clickhouseusername};${var.clickhousepassword}"
  depends_on   = [osc_clickhouse_clickhouse.clickhouse_instance]
}

resource "osc_grafana_grafana" "this" {
  depends_on         = [osc_secret.grafanadatasource]
  name               = var.analyticspeline_name
  anonymous_enabled  = false
  plugins_preinstall = "vertamedia-clickhouse-datasource,grafana-clickhouse-datasource"
  datasources        = format("{{secrets.%s}}", osc_secret.grafanadatasource.secret_name)
  dashboard_urls     = var.grafanadashboardurl
}

############################
# Outputs
############################

## --- SmoothMQ ---
output "smoothmq_instance_url" {
  value = osc_poundifdef_smoothmq.smooth_mq_instance.instance_url
}
output "smoothmq_service_id" {
  value = osc_poundifdef_smoothmq.smooth_mq_instance.service_id
}

## --- Clickhouse ---
output "clickhouse_external_ip" {
  value = osc_clickhouse_clickhouse.clickhouse_instance.external_ip
}
output "clickhouse_external_port" {
  value = osc_clickhouse_clickhouse.clickhouse_instance.external_port
}
output "clickhouse_instance_url" {
  value = osc_clickhouse_clickhouse.clickhouse_instance.instance_url
}
output "clickhouse_service_id" {
  value = osc_clickhouse_clickhouse.clickhouse_instance.service_id
}

## --- Player Analytics Eventsink ---
output "eventsink_instance_url" {
  value = osc_eyevinn_player_analytics_eventsink.eventsink_instance.instance_url
}
output "eventsink_service_id" {
  value = osc_eyevinn_player_analytics_eventsink.eventsink_instance.service_id
}

## --- Player Analytics Worker ---
output "worker_instance_url" {
  value = osc_eyevinn_player_analytics_worker.worker_instance.instance_url
}
output "worker_service_id" {
  value = osc_eyevinn_player_analytics_worker.worker_instance.service_id
}

## --- Grafana ---
output "grafana_instance_url" {
  value = osc_grafana_grafana.this.instance_url
}
output "grafana_external_ip" {
  value = osc_grafana_grafana.this.external_ip
}
output "grafana_external_port" {
  value = osc_grafana_grafana.this.external_port
}
