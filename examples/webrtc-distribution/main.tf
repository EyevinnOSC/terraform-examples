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

variable "distribution_name" {
  type        = string
  default     = "mydistribution"
  description = "Name of the distribution. Lower case letters and numbers only"
}

# Symphony Media Bridge API key. Sensitive
variable "smb_api_key" {
  type        = string
  sensitive   = true
  description = "Symphony Media Bridge API key"
}

variable "whip_key" {
  type        = string
  sensitive   = true
  description = "Ingest key"
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

resource "osc_secret" "smbapikey" {
  service_ids  = ["eyevinn-wrtc-egress", "eyevinn-docker-wrtc-sfu", "eyevinn-smb-whip-bridge"]
  secret_name  = "${var.distribution_name}smbapikey"
  secret_value = var.smb_api_key
}

############################
# Resource: Symphony Media Bridge
############################
resource "osc_eyevinn_docker_wrtc_sfu" "this" {
  name    = var.distribution_name
  api_key = format("{{secrets.%s}}", osc_secret.smbapikey.secret_name)
}

############################
# Resource: WHEP Gateway
############################
resource "osc_eyevinn_wrtc_egress" "this" {
  name        = var.distribution_name
  smb_url     = osc_eyevinn_docker_wrtc_sfu.this.instance_url
  smb_api_key = format("{{secrets.%s}}", osc_secret.smbapikey.secret_name)

  depends_on = [osc_eyevinn_docker_wrtc_sfu.this]
}

############################
# Resource: WHIP Gateway
############################
resource "osc_eyevinn_smb_whip_bridge" "this" {
  name              = var.distribution_name
  smb_url           = osc_eyevinn_docker_wrtc_sfu.this.instance_url
  smb_api_key       = format("{{secrets.%s}}", osc_secret.smbapikey.secret_name)
  whip_api_key      = var.whip_key
  whep_endpoint_url = osc_eyevinn_wrtc_egress.this.instance_url
  depends_on        = [osc_eyevinn_docker_wrtc_sfu.this, osc_eyevinn_wrtc_egress.this]
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

## --- WHEP Gateway ---
output "WHEP_external_ip" {
  value = osc_eyevinn_wrtc_egress.this.external_ip
}
output "WHEP_external_port" {
  value = osc_eyevinn_wrtc_egress.this.external_port
}
output "WHEP_instance_url" {
  value = osc_eyevinn_wrtc_egress.this.instance_url
}
output "WHEP_service_id" {
  value = osc_eyevinn_wrtc_egress.this.service_id
}

## --- WHIP Gateway ---
output "WHIP_external_ip" {
  value = osc_eyevinn_smb_whip_bridge.this.external_ip
}
output "WHIP_external_port" {
  value = osc_eyevinn_smb_whip_bridge.this.external_port
}
output "WHIP_instance_url" {
  value = osc_eyevinn_smb_whip_bridge.this.instance_url
}
output "WHIP_service_id" {
  value = osc_eyevinn_smb_whip_bridge.this.service_id
}
