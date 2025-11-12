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

variable "intercom_name" {
  type        = string
  default     = "myintercom"
  description = "Name of the intercom system. Lower case letters and numbers only"
}

# Intercom SMB API key. Sensitive
variable "smb_api_key" {
  type        = string
  default     = null
  sensitive   = true
  description = "Set the Symphony Media Bridge API key. Leave empty to have it auto-generated"
}

## --- Intercom DB ---
# Password for admin user. Sensitive
variable "db_admin_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Set the the database password. Leave empty to have it auto-generated"
}

# Name of the actual database to create
variable "db_name" {
  type        = string
  default     = "intercom"
  description = "Name of the database for the Intercom system"
}

locals {
  base_host = trimprefix("${osc_apache_couchdb.this.instance_url}", "https://")
}

locals {
  smb_api_key_final = var.smb_api_key != null && var.smb_api_key != "null" ? var.smb_api_key : random_password.smb_api_key.result
}

locals {
  db_admin_password_final = var.db_admin_password != null && var.smb_api_key != "null" ? var.db_admin_password : random_password.db_admin_password.result
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
resource "random_password" "smb_api_key" {
  length  = 16
  special = false
}

resource "random_password" "db_admin_password" {
  length  = 16
  special = false
}


############################
# Resource: Secrets
############################

resource "osc_secret" "token" {
  service_ids  = ["eyevinn-intercom-manager"]
  secret_name  = "${var.intercom_name}oscpat"
  secret_value = var.osc_pat
}

resource "osc_secret" "apikey" {
  service_ids  = ["eyevinn-intercom-manager", "eyevinn-docker-wrtc-sfu"]
  secret_name  = "${var.intercom_name}smbapikey"
  secret_value = local.smb_api_key_final
}

resource "osc_secret" "dbadminpassword" {
  service_ids  = ["apache-couchdb"]
  secret_name  = "${var.intercom_name}dbadminpass"
  secret_value = local.db_admin_password_final
}

resource "osc_secret" "dburl" {
  service_ids  = ["eyevinn-intercom-manager"]
  secret_name  = "${var.intercom_name}dburl"
  secret_value = "https://admin:${local.db_admin_password_final}@${local.base_host}/${var.db_name}"
}

############################
# Resource: Symphony Media Bridge
############################
resource "osc_eyevinn_docker_wrtc_sfu" "this" {
  name    = var.intercom_name
  api_key = format("{{secrets.%s}}", osc_secret.apikey.secret_name)
}

############################
# Resource: CouchDB
############################

resource "osc_apache_couchdb" "this" {
  name           = var.intercom_name
  admin_password = format("{{secrets.%s}}", osc_secret.dbadminpassword.secret_name)
}

############################
# Resource: Null
############################

## Create the database. Need to retry until database instance is ready
resource "null_resource" "wait_for_couchdb" {
  depends_on = [osc_apache_couchdb.this]

  provisioner "local-exec" {
    command     = "${path.module}/createnewdb.sh ${osc_secret.dburl.secret_value}"
    interpreter = ["/bin/bash", "-c"]
  }
}


############################
# Resource: Eyevinn Intercom Manager
############################
resource "osc_eyevinn_intercom_manager" "this" {
  name        = var.intercom_name
  smb_url     = osc_eyevinn_docker_wrtc_sfu.this.instance_url
  smb_api_key = format("{{secrets.%s}}", osc_secret.apikey.secret_name)
  db_url      = format("{{secrets.%s}}", osc_secret.dburl.secret_name)

  depends_on = [null_resource.wait_for_couchdb]

  # Optional: providing your OSC token here allows auto re-auth/sharing features
  # (can be omitted if not needed)
  osc_access_token = format("{{secrets.%s}}", osc_secret.token.secret_name)
}

############################
# Outputs
############################

## --- SMB ---
output "SFU_external_ip" {
  value = osc_eyevinn_docker_wrtc_sfu.this.external_ip
}
output "SFU_external_port" {
  value = osc_eyevinn_docker_wrtc_sfu.this.external_port
}
output "SFU_instance_url" {
  value = osc_eyevinn_docker_wrtc_sfu.this.instance_url
}
output "SFU_service_id" {
  value = osc_eyevinn_docker_wrtc_sfu.this.service_id
}

## --- Intercom Manager ---
output "Manager_external_ip" {
  value = osc_eyevinn_intercom_manager.this.external_ip
}
output "Manager_external_port" {
  value = osc_eyevinn_intercom_manager.this.external_port
}
output "Manager_instance_url" {
  value = osc_eyevinn_intercom_manager.this.instance_url
}
output "Manager_service_id" {
  value = osc_eyevinn_intercom_manager.this.service_id
}

## --- Intercom Database ---
output "Database_external_ip" {
  value = osc_apache_couchdb.this.external_ip
}
output "Database_external_port" {
  value = osc_apache_couchdb.this.external_port
}
output "Database_instance_url" {
  value = osc_apache_couchdb.this.instance_url
}
output "Database_service_id" {
  value = osc_apache_couchdb.this.service_id
}
