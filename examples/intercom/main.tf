terraform {
  required_version = ">= 1.6.0" # Compatible with Terraform >= 1.6.0 and OpenTofu >= 1.6.0
  required_providers {
    osc = {
      source  = "registry.terraform.io/EyevinnOSC/osc"
      version = "0.1.5"
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

## --- Intercom SMB ---
# A friendly name for the SMB
variable "intercom_smb_name" {
  type        = string
  default     = "examplesmb"
  description = "Name of the SMB. Lower case letters and numbers only"
}

# Intercom SMB API key. Sensitive
variable "smb_api_key" {
  type        = string
  sensitive   = true
  description = "Symphony Media Bridge API key"
}

## --- Intercom Manager --- 
# A friendly name for the Intercom manager
variable "intercom_manager_name" {
  type        = string
  default     = "exampleintercommanager"
  description = "Name of the Intercom system. Lower case letters and numbers only"
}

## --- Intercom DB ---
# Password for admin user. Sensitive
variable "db_admin_password" {
  type        = string
  default     = "secretePassword"
  sensitive   = true
  description = "The DB password"
}

# A friendly name for the database instance
variable "intercom_db_name" {
  type        = string
  default     = "exampleintercomdatabase"
  description = "Name of the database instance for the Intercom system. Lower case letters and numbers only"
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

############################
# Provider
############################
provider "osc" {
  pat         = var.osc_pat
  environment = var.osc_environment
}

############################
# Resource: Secrets
############################

resource "osc_secret" "token" {
  service_ids  = ["eyevinn-intercom-manager"]
  secret_name  = "terraformoscpat"
  secret_value = var.osc_pat
}

resource "osc_secret" "apikey" {
  service_ids  = ["eyevinn-intercom-manager", "eyevinn-docker-wrtc-sfu"]
  secret_name  = "terraformsmbapikey"
  secret_value = var.smb_api_key
}

resource "osc_secret" "dbadminpassword" {
  service_ids  = ["apache-couchdb"]
  secret_name  = "terraformdbadminpass"
  secret_value = var.db_admin_password
}

resource "osc_secret" "dburl" {
  service_ids  = ["eyevinn-intercom-manager"]
  secret_name  = "terraformdburl"
  secret_value = "https://admin:${var.db_admin_password}@${local.base_host}/${var.db_name}"
}

############################
# Resource: Symphony Media Bridge
############################
resource "osc_eyevinn_docker_wrtc_sfu" "this" {
  name    = var.intercom_smb_name
  api_key = format("{{secrets.%s}}", osc_secret.apikey.secret_name)
}

############################
# Resource: CouchDB
############################

resource "osc_apache_couchdb" "this" {
  name           = var.intercom_db_name
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
  name        = var.intercom_manager_name
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
