terraform {
  required_version = ">= 1.6.0" # Compatible with Terraform >= 1.6.0 and OpenTofu >= 1.6.0
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

variable "paramstore_name" {
  type        = string
  default     = "myparamstore"
  description = "Name of the paramstore solution. Lower case letters and numbers only"
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

resource "osc_secret" "valkeypassword" {
  service_ids  = ["valkey-io-valkey"]
  secret_name  = "${var.paramstore_name}valkeypassword"
  secret_value = local.valkey_password_final

  lifecycle {
    create_before_destroy = true
  }
}

resource "osc_secret" "redis_url" {
  service_ids  = ["eyevinn-app-config-svc"]
  secret_name  = "${var.paramstore_name}redisurl"
  secret_value = local.valkey_redis_url
  depends_on   = [osc_valkey_io_valkey.this]
}

############################
# Resource: Valkey
############################
resource "osc_valkey_io_valkey" "this" {
  name     = var.paramstore_name
  password = format("{{secrets.%s}}", osc_secret.valkeypassword.secret_name)
}

############################
# Resource: App Config Service
############################
resource "osc_eyevinn_app_config_svc" "this" {
  name      = var.paramstore_name
  redis_url = format("{{secrets.%s}}", osc_secret.redis_url.secret_name)

  depends_on = [osc_valkey_io_valkey.this, osc_secret.redis_url]
}

############################
# Outputs
############################

## --- Valkey ---
output "valkey_external_ip" {
  value = osc_valkey_io_valkey.this.external_ip
}
output "valkey_external_port" {
  value = osc_valkey_io_valkey.this.external_port
}
output "valkey_instance_url" {
  value = osc_valkey_io_valkey.this.instance_url
}
output "valkey_service_id" {
  value = osc_valkey_io_valkey.this.service_id
}

## --- App Config Service ---
output "app_config_svc_external_ip" {
  value = osc_eyevinn_app_config_svc.this.external_ip
}
output "app_config_svc_external_port" {
  value = osc_eyevinn_app_config_svc.this.external_port
}
output "app_config_svc_instance_url" {
  value = osc_eyevinn_app_config_svc.this.instance_url
}
output "app_config_svc_service_id" {
  value = osc_eyevinn_app_config_svc.this.service_id
}
