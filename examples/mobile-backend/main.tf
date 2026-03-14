terraform {
  required_version = ">= 1.6.0"
  required_providers {
    osc = {
      source  = "registry.terraform.io/EyevinnOSC/osc"
      version = "0.6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

############################
# Variables
############################

variable "osc_pat" {
  type        = string
  sensitive   = true
  description = "Eyevinn OSC Personal Access Token"
}

variable "osc_environment" {
  type        = string
  default     = "prod"
  description = "OSC Environment"
}

variable "solution_name" {
  type        = string
  default     = "mybackend"
  description = "Name prefix for all services. Lowercase letters and numbers only"
}

variable "smtp_url" {
  type        = string
  description = "SMTP URL for email verification. OSC paid tenants: use OSC mailbox SMTP credentials from Team Settings > Email"
}

variable "database_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "PostgreSQL password. Leave empty to auto-generate"
}

variable "couchdb_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "CouchDB admin password. Leave empty to auto-generate"
}

variable "minio_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "MinIO admin password. Leave empty to auto-generate"
}

variable "valkey_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Valkey password. Leave empty to auto-generate"
}

############################
# Provider
############################

provider "osc" {
  pat         = var.osc_pat
  environment = var.osc_environment
}

############################
# Random Passwords
############################

resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "random_password" "couchdb_password" {
  length  = 16
  special = false
}

resource "random_password" "minio_password" {
  length      = 16
  special     = false
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}

resource "random_password" "valkey_password" {
  length  = 16
  special = false
}

locals {
  db_password_final      = var.database_password != null && var.database_password != "null" ? var.database_password : random_password.db_password.result
  couchdb_password_final = var.couchdb_password != null && var.couchdb_password != "null" ? var.couchdb_password : random_password.couchdb_password.result
  minio_password_final   = var.minio_password != null && var.minio_password != "null" ? var.minio_password : random_password.minio_password.result
  valkey_password_final  = var.valkey_password != null && var.valkey_password != "null" ? var.valkey_password : random_password.valkey_password.result
  minio_user             = "minioadmin"
}

############################
# Secrets
############################

resource "osc_secret" "dbpwd" {
  service_ids  = ["birme-osc-postgresql", "postgrest-postgrest"]
  secret_name  = "${var.solution_name}dbpwd"
  secret_value = local.db_password_final

  lifecycle {
    create_before_destroy = true
  }
}

resource "osc_secret" "couchpwd" {
  service_ids  = ["apache-couchdb", "eyevinn-openauth-pwd"]
  secret_name  = "${var.solution_name}couchpwd"
  secret_value = local.couchdb_password_final

  lifecycle {
    create_before_destroy = true
  }
}

resource "osc_secret" "miniopwd" {
  service_ids  = ["minio-minio"]
  secret_name  = "${var.solution_name}miniopwd"
  secret_value = local.minio_password_final

  lifecycle {
    create_before_destroy = true
  }
}

resource "osc_secret" "miniouser" {
  service_ids  = ["minio-minio"]
  secret_name  = "${var.solution_name}miniouser"
  secret_value = local.minio_user

  lifecycle {
    create_before_destroy = true
  }
}

resource "osc_secret" "valkeypwd" {
  service_ids  = ["valkey-io-valkey"]
  secret_name  = "${var.solution_name}valkeypwd"
  secret_value = local.valkey_password_final

  lifecycle {
    create_before_destroy = true
  }
}

############################
# Phase 1: Infrastructure Services
############################

resource "osc_birme_osc_postgresql" "this" {
  name              = var.solution_name
  postgres_password = format("{{secrets.%s}}", osc_secret.dbpwd.secret_name)
  postgres_db       = "mobileapp"
  postgres_user     = "appuser"
}

resource "osc_apache_couchdb" "this" {
  name           = var.solution_name
  admin_password = format("{{secrets.%s}}", osc_secret.couchpwd.secret_name)
}

resource "osc_valkey_io_valkey" "this" {
  name     = var.solution_name
  password = format("{{secrets.%s}}", osc_secret.valkeypwd.secret_name)
}

resource "osc_minio_minio" "this" {
  name          = var.solution_name
  root_user     = format("{{secrets.%s}}", osc_secret.miniouser.secret_name)
  root_password = format("{{secrets.%s}}", osc_secret.miniopwd.secret_name)
}

resource "osc_flyimg_flyimg" "this" {
  name = var.solution_name
}

############################
# Phase 2: API Layer
############################

resource "osc_postgrest_postgrest" "this" {
  name         = var.solution_name
  db_uri       = format("postgresql://appuser:{{secrets.%s}}@%s:%d/mobileapp", osc_secret.dbpwd.secret_name, osc_birme_osc_postgresql.this.external_ip, osc_birme_osc_postgresql.this.external_port)
  db_anon_role = "appuser"
  db_schemas   = "public"
  depends_on   = [osc_birme_osc_postgresql.this]
}

############################
# Phase 3: Auth Layer
############################

resource "osc_eyevinn_openauth_pwd" "this" {
  name            = var.solution_name
  user_db_url     = format("http://admin:{{secrets.%s}}@%s:%d", osc_secret.couchpwd.secret_name, osc_apache_couchdb.this.external_ip, osc_apache_couchdb.this.external_port)
  smtp_mailer_url = var.smtp_url
  depends_on      = [osc_apache_couchdb.this]
}

############################
# Outputs
############################

output "postgresql_url" {
  value       = format("postgresql://appuser@%s:%d/mobileapp", osc_birme_osc_postgresql.this.external_ip, osc_birme_osc_postgresql.this.external_port)
  description = "PostgreSQL connection URL (add password to connect)"
}

output "rest_api_url" {
  value       = osc_postgrest_postgrest.this.instance_url
  description = "PostgREST auto-generated REST API URL"
}

output "minio_console_url" {
  value       = osc_minio_minio.this.instance_url
  description = "MinIO console URL"
}

output "minio_endpoint" {
  value       = format("%s:%d", osc_minio_minio.this.external_ip, osc_minio_minio.this.external_port)
  description = "MinIO S3-compatible endpoint (host:port)"
}

output "minio_access_key" {
  value       = local.minio_user
  description = "MinIO access key (S3 access key ID)"
}

output "auth_url" {
  value       = osc_eyevinn_openauth_pwd.this.instance_url
  description = "OpenAuth Password service URL"
}

output "valkey_url" {
  value       = format("redis://%s:%d", osc_valkey_io_valkey.this.external_ip, osc_valkey_io_valkey.this.external_port)
  description = "Valkey (Redis-compatible) connection URL"
}

output "flyimg_url" {
  value       = osc_flyimg_flyimg.this.instance_url
  description = "Flyimg image transform service URL"
}
