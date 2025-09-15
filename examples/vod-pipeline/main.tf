terraform {
  required_version = ">= 1.6.0"
  required_providers {
    osc = {
      source  = "EyevinnOSC/osc"
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

## --- MinIO storage
variable "minio_instance_name" {
  type        = string
  description = "The instance name. Shown in the OSC APP UI. Lower case letters and numbers only "
  default     = "minio"
}

variable "minio_username" {
  type        = string
  sensitive   = true
  description = "The minio user name"
}

variable "minio_password" {
  type        = string
  sensitive   = true
  description = "The minio password"
}

## --- Encore ---
variable "encore_instance_name" {
  type        = string
  description = "The instance name. Shown in the OSC App UI. Lower case letters and numbers only"
  default     = "encore"
}

variable "encore_bucket" {
  type        = string
  default     = "encore"
  description = "The bucket used for encore inputs and outputs"
}

# --- Valkey
variable "valkey_instance_name" {
  type        = string
  default     = "valkey"
  description = "The instance name. Shown in the OSC APP UI. Lower case letters and numbers only"
}

variable "valkey_password" {
  type        = string
  sensitive   = true
  description = "password for Valkey"
}

# --- Encore Callback Listener
variable "encore_cb_instance_name" {
  type        = string
  default     = "encorecb"
  description = "The instance name. Shown in the OSC APP UI. Lower case letters and numbers only"
}

variable "encore_cb_redis_queue" {
  type        = string
  default     = "package"
  description = "The name of the queue. Optional"
}

# --- Encore Packager
variable "encore_packager_instance_name" {
  type        = string
  default     = "encorepackager"
  description = "The instance name. Shown in the OSC APP UI. Lower case letters and numbers only"
}

variable "encore_packager_bucket" {
  type        = string
  default     = "encore_packager"
  description = "The bucket used for the encore packager output"
}

variable "encore_packager_output_folder" {
  type        = string
  default     = "packager_output"
  description = "The output folder for the packager. Should be in form 'folder1/folder2/../lastfolder'"
}

# Environment prod|stage|dev
variable "osc_environment" {
  type        = string
  default     = "prod"
  description = "OSC Environment"

}

locals {
  valkey_redis_url = var.valkey_password == "" ? format("redis://%s:%d", osc_valkey_io_valkey.this.external_ip, osc_valkey_io_valkey.this.external_port) : format("redis://default:%s@%s:%d", var.valkey_password, osc_valkey_io_valkey.this.external_ip, osc_valkey_io_valkey.this.external_port)
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

resource "osc_secret" "miniousername" {
  service_ids  = ["minio-minio", "encore", "eyevinn-encore-packager"]
  secret_name  = "terraformminiousername"
  secret_value = var.minio_username
}

resource "osc_secret" "miniopassword" {
  service_ids  = ["minio-minio", "encore", "eyevinn-encore-packager"]
  secret_name  = "terraformminiopassword"
  secret_value = var.minio_password
}

resource "osc_secret" "valkeypassword" {
  service_ids  = ["valkey-io-valkey"]
  secret_name  = "terraformvalkeypassword"
  secret_value = var.valkey_password
}

resource "osc_secret" "token" {
  service_ids  = ["eyevinn-encore-packager"]
  secret_name  = "terraformoscpat"
  secret_value = var.osc_pat
}


############################
# Resource: Minio storage
############################
resource "osc_minio_minio" "this" {
  name          = var.minio_instance_name
  root_user     = format("{{secrets.%s}}", osc_secret.miniousername.secret_name)
  root_password = format("{{secrets.%s}}", osc_secret.miniopassword.secret_name)
}

############################
# Resource: Null
############################

## Create the buckets. Need to retry until storage instance is ready
resource "null_resource" "create_buckets" {
  depends_on = [osc_minio_minio.this]

  provisioner "local-exec" {
    command     = "${path.module}/create_buckets.sh ${osc_minio_minio.this.instance_url} ${var.encore_bucket} ${var.encore_packager_bucket}"
    interpreter = ["/bin/bash", "-c"]
  }
}

############################
# Resource: Encore
############################
resource "osc_encore" "this" {
  name                 = var.encore_instance_name
  s3_access_key_id     = osc_minio_minio.this.root_user
  s3_secret_access_key = osc_minio_minio.this.root_password

  s3_endpoint = osc_minio_minio.this.instance_url #Use the URL from the minio instance created

  depends_on = [null_resource.create_buckets]
}

############################
# Resource: Valkey
############################

resource "osc_valkey_io_valkey" "this" {
  name = var.valkey_instance_name

  password = format("{{secrets.%s}}", osc_secret.valkeypassword.secret_name)

  depends_on = [osc_encore.this]
}

resource "osc_secret" "redis_url" {
  service_ids  = ["eyevinn-encore-callback-listener", "eyevinn-encore-packager"]
  secret_name  = "terraformredisurl"
  secret_value = local.valkey_redis_url
  depends_on   = [osc_valkey_io_valkey.this]
}

############################
# Resource: Encore Callback Listener
############################

resource "osc_eyevinn_encore_callback_listener" "this" {
  name      = var.encore_cb_instance_name
  redis_url = format("{{secrets.%s}}", osc_secret.redis_url.secret_name)
  #redis_url   = local.valkey_redis_url
  encore_url  = trimsuffix(osc_encore.this.instance_url, "/")
  redis_queue = var.encore_cb_redis_queue

  depends_on = [osc_secret.redis_url]
}

############################
# Resource: Encore Packager
############################
resource "osc_eyevinn_encore_packager" "this" {
  name = var.encore_packager_instance_name

  redis_url             = format("{{secrets.%s}}", osc_secret.redis_url.secret_name)
  aws_access_key_id     = osc_minio_minio.this.root_user
  aws_secret_access_key = osc_minio_minio.this.root_password
  output_folder         = format("s3://%s/%s/", var.encore_packager_bucket, var.encore_packager_output_folder)
  personal_access_token = format("{{secrets.%s}}", osc_secret.token.secret_name)

  # optionals
  aws_region      = osc_encore.this.s3_region
  s3_endpoint_url = osc_minio_minio.this.instance_url
  redis_queue     = osc_eyevinn_encore_callback_listener.this.redis_queue

  depends_on = [osc_eyevinn_encore_callback_listener.this]
}


############################
# Outputs
############################

## --- MinIO ---
output "minio_external_ip" {
  value = osc_minio_minio.this.external_ip
}
output "minio_external_port" {
  value = osc_minio_minio.this.external_port
}
output "minio_instance_url" {
  value = osc_minio_minio.this.instance_url
}
output "minio_service_id" {
  value = osc_minio_minio.this.service_id
}

## --- Encore ---
output "encore_external_ip" {
  value = osc_encore.this.external_ip
}
output "encore_external_port" {
  value = osc_encore.this.external_port
}
output "encore_instance_url" {
  value = osc_encore.this.instance_url
}
output "encore_service_id" {
  value = osc_encore.this.service_id
}

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

## --- Encore Callback Listener ---
output "encore_callback_listener_external_ip" {
  value = osc_eyevinn_encore_callback_listener.this.external_ip
}
output "encore_callback_listener_external_port" {
  value = osc_eyevinn_encore_callback_listener.this.external_port
}
output "encore_callback_listener_instance_url" {
  value = osc_eyevinn_encore_callback_listener.this.instance_url
}
output "encore_callback_listener_service_id" {
  value = osc_eyevinn_encore_callback_listener.this.service_id
}

## --- Encore Packager ---
output "encore_packager_external_ip" {
  value = osc_eyevinn_encore_packager.this.external_ip
}
output "encore_packager_external_port" {
  value = osc_eyevinn_encore_packager.this.external_port
}
output "encore_packager_instance_url" {
  value = osc_eyevinn_encore_packager.this.instance_url
}
output "encore_packager_service_id" {
  value = osc_eyevinn_encore_packager.this.service_id
}
