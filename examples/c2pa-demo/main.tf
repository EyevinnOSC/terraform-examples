terraform {
  required_version = ">= 1.6.0"
  required_providers {
    osc = {
      source  = "registry.terraform.io/EyevinnOSC/osc"
      version = "0.5.0"
    }
  }
}

############################
# Variables (inputs)
############################

## --- General ---

variable "osc_pat" {
  type        = string
  sensitive   = true
  description = "Eyevinn OSC Personal Access Token"
}

variable "osc_environment" {
  type        = string
  default     = "prod"
  description = "OSC Environment (prod/stage/dev)"
}

variable "name" {
  type        = string
  default     = "c2pademo"
  description = "Solution name. Lower case letters and numbers only"
}

## --- MinIO ---

variable "minio_username" {
  type        = string
  sensitive   = true
  description = "MinIO root username"
}

variable "minio_password" {
  type        = string
  sensitive   = true
  description = "MinIO root password"
}

variable "minio_bucket" {
  type        = string
  default     = "c2pa"
  description = "S3 bucket name for C2PA content"
}

## --- Valkey ---

variable "valkey_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Password for Valkey. Leave empty to auto-generate"
}

locals {
  valkey_password_final = var.valkey_password != null && var.valkey_password != "null" ? var.valkey_password : random_password.valkey_password.result
  valkey_redis_url      = format("redis://default:%s@%s:%d", local.valkey_password_final, osc_valkey_io_valkey.this.external_ip, osc_valkey_io_valkey.this.external_port)
}

############################
# Provider
############################
provider "osc" {
  pat         = var.osc_pat
  environment = var.osc_environment
}

############################
# Resource: Random passwords
############################
resource "random_password" "valkey_password" {
  length  = 16
  special = false
}

############################
# Resource: Secrets
############################

resource "osc_secret" "miniousername" {
  service_ids  = ["minio-minio"]
  secret_name  = "${var.name}miniousername"
  secret_value = var.minio_username
}

resource "osc_secret" "miniopassword" {
  service_ids  = ["minio-minio"]
  secret_name  = "${var.name}miniopassword"
  secret_value = var.minio_password
}

resource "osc_secret" "valkeypassword" {
  service_ids  = ["valkey-io-valkey"]
  secret_name  = "${var.name}valkeypassword"
  secret_value = local.valkey_password_final

  lifecycle {
    create_before_destroy = true
  }
}

resource "osc_secret" "redis_url" {
  service_ids  = ["eyevinn-app-config-svc"]
  secret_name  = "${var.name}redisurl"
  secret_value = local.valkey_redis_url
  depends_on   = [osc_valkey_io_valkey.this]
}

############################
# Resource: MinIO storage
############################
resource "osc_minio_minio" "this" {
  name          = var.name
  root_user     = format("{{secrets.%s}}", osc_secret.miniousername.secret_name)
  root_password = format("{{secrets.%s}}", osc_secret.miniopassword.secret_name)
}

############################
# Resource: Create S3 bucket
############################
resource "null_resource" "create_bucket" {
  depends_on = [osc_minio_minio.this]

  provisioner "local-exec" {
    command     = "${path.module}/create_bucket.sh ${osc_minio_minio.this.instance_url} ${var.minio_bucket}"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      AWS_ACCESS_KEY_ID     = var.minio_username
      AWS_SECRET_ACCESS_KEY = var.minio_password
    }
  }
}

############################
# Resource: Valkey
############################
resource "osc_valkey_io_valkey" "this" {
  name     = var.name
  password = format("{{secrets.%s}}", osc_secret.valkeypassword.secret_name)
}

############################
# Resource: App Config Service (Parameter Store)
############################
resource "osc_eyevinn_app_config_svc" "this" {
  name      = var.name
  redis_url = format("{{secrets.%s}}", osc_secret.redis_url.secret_name)

  depends_on = [osc_valkey_io_valkey.this, osc_secret.redis_url]
}

############################
# Seed parameter store with config values
############################
resource "null_resource" "seed_config" {
  depends_on = [
    osc_eyevinn_app_config_svc.this,
    osc_minio_minio.this,
    osc_valkey_io_valkey.this,
    null_resource.create_bucket
  ]

  provisioner "local-exec" {
    command     = "${path.module}/seed_config.sh"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      CONFIG_URL       = osc_eyevinn_app_config_svc.this.instance_url
      MINIO_ENDPOINT   = osc_minio_minio.this.instance_url
      MINIO_ACCESS_KEY = var.minio_username
      MINIO_SECRET_KEY = var.minio_password
      MINIO_BUCKET     = var.minio_bucket
      VALKEY_URL       = local.valkey_redis_url
    }
  }
}

############################
# Resource: Web Runner — C2PA Signer
############################
resource "osc_eyevinn_web_runner" "signer" {
  name           = "${var.name}signer"
  source_url     = "https://github.com/Eyevinn/c2pa-demo-signer"
  config_service = var.name

  depends_on = [null_resource.seed_config]
}

############################
# Seed SIGNER_URL into parameter store (needs signer URL)
############################
resource "null_resource" "seed_signer_url" {
  depends_on = [osc_eyevinn_web_runner.signer]

  provisioner "local-exec" {
    command = <<-EOT
      sleep 5
      curl -sf -X PUT "${osc_eyevinn_app_config_svc.this.instance_url}/api/v1/config/SIGNER_URL" \
        -H "Content-Type: application/json" \
        -d '{"value": "${osc_eyevinn_web_runner.signer.instance_url}"}'
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

############################
# Resource: Web Runner — C2PA Landing Page
############################
resource "osc_eyevinn_web_runner" "landing" {
  name           = "${var.name}landing"
  source_url     = "https://github.com/Eyevinn/c2pa-demo-landing"
  config_service = var.name

  depends_on = [null_resource.seed_signer_url]
}

############################
# Outputs
############################

## --- Landing Page (main entry point) ---
output "demo_url" {
  value       = osc_eyevinn_web_runner.landing.instance_url
  description = "C2PA Demo Platform URL"
}

output "emsg_player_url" {
  value       = "${osc_eyevinn_web_runner.landing.instance_url}/emsg/?demo=true"
  description = "emsg (Unified Streaming) demo player"
}

output "uuid_player_url" {
  value       = "${osc_eyevinn_web_runner.landing.instance_url}/uuid/?demo=true"
  description = "uuid (EZDRM/Qualabs) demo player"
}

## --- Signer ---
output "signer_url" {
  value = osc_eyevinn_web_runner.signer.instance_url
}

output "signer_service_id" {
  value = osc_eyevinn_web_runner.signer.service_id
}

## --- MinIO ---
output "minio_instance_url" {
  value = osc_minio_minio.this.instance_url
}

output "minio_service_id" {
  value = osc_minio_minio.this.service_id
}

## --- Valkey ---
output "valkey_instance_url" {
  value = osc_valkey_io_valkey.this.instance_url
}

output "valkey_service_id" {
  value = osc_valkey_io_valkey.this.service_id
}

## --- App Config Service ---
output "config_service_url" {
  value = osc_eyevinn_app_config_svc.this.instance_url
}
