terraform {
  required_version = ">= 1.6.0" # Compatible with Terraform >= 1.6.0 and OpenTofu >= 1.6.0
  required_providers {
    osc = {
      source  = "registry.terraform.io/EyevinnOSC/osc"
      version = "0.3.0"
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

# Environment 
variable "osc_environment" {
  type        = string
  default     = "prod"
  description = "OSC Environment"
}

variable "penpot_name" {
  type        = string
  default     = "mypenpot"
  description = "Name of the Penpot solution. Lower case letters and numbers only"
}

variable "database_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Set the PostgreSQL database password. Leave empty to have it auto-generated"
}

locals {
  db_password_final = var.database_password != null && var.database_password != "null" ? var.database_password : random_password.db_password.result
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
resource "random_password" "db_password" {
  length  = 16
  special = false
}

############################
# Resource: Secrets
############################

resource "osc_secret" "dbpwd" {
  service_ids  = ["penpot-penpot", "birme-osc-postgresql"]
  secret_name  = "${var.penpot_name}dbpwd"
  secret_value = local.db_password_final
  
  lifecycle {
    create_before_destroy = true
  }
}

############################
# Resource: PostgreSQL Database
############################
resource "osc_birme_osc_postgresql" "this" {
  name                  = var.penpot_name
  postgres_password     = format("{{secrets.%s}}", osc_secret.dbpwd.secret_name)
  postgres_db           = "penpot"
  postgres_init_db_args = "--data-checksums"
  postgres_user         = "penpot"
}

############################
# Resource: Valkey
############################
resource "osc_valkey_io_valkey" "this" {
  name      = var.penpot_name
}

############################
# Resource: Penpot
############################
resource "osc_penpot_penpot" "this" {
  name               = var.penpot_name
  db_url             = format("postgresql://%s:%d/penpot", osc_birme_osc_postgresql.this.external_ip, osc_birme_osc_postgresql.this.external_port)
  db_username        = "penpot"
  db_password        = format("{{secrets.%s}}", osc_secret.dbpwd.secret_name)
  redis_url          = format("redis://%s:%d", osc_valkey_io_valkey.this.external_ip, osc_valkey_io_valkey.this.external_port)
  depends_on         = [osc_birme_osc_postgresql.this, osc_valkey_io_valkey.this]
}

############################
# Outputs
############################

## --- Database ---
output "DB_external_ip" {
  value = osc_birme_osc_postgresql.this.external_ip
}
output "DB_external_port" {
  value = osc_birme_osc_postgresql.this.external_port
}
output "DB_instance_url" {
  value = osc_birme_osc_postgresql.this.instance_url
}
output "DB_service_id" {
  value = osc_birme_osc_postgresql.this.service_id
}

## --- Valkey ---
output "Valkey_external_ip" {
  value = osc_valkey_io_valkey.this.external_ip
}
output "Valkey_external_port" {
  value = osc_valkey_io_valkey.this.external_port
}
output "Valkey_instance_url" {
  value = osc_valkey_io_valkey.this.instance_url
}
output "Valkey_service_id" {
  value = osc_valkey_io_valkey.this.service_id
}
