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

# Environment prod|stage|dev
variable "osc_environment" {
  type        = string
  default     = "prod"
  description = "OSC Environment"

}

variable "adpipeline_name" {
  type        = string
  default     = "myadpipeline"
  description = "Name of the ad-pipeline. Lower case letters and numbers only"
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

variable "encore_bucket" {
  type        = string
  default     = "encore"
  description = "The bucket used for encore inputs and outputs"
}

variable "valkey_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = "password for Valkey"
}

variable "encore_packager_queue" {
  type        = string
  default     = "adPackager"
  description = "Queue name for packager jobs"
}

variable "encore_packager_bucket" {
  type        = string
  default     = "encorepackager"
  description = "The bucket used for the encore packager output"
}

variable "encore_packager_output_folder" {
  type        = string
  default     = "packager_output"
  description = "The output folder for the packager. Should be in form 'folder1/folder2/../lastfolder'"
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
  secret_name  = "${var.adpipeline_name}miniousername"
  secret_value = var.minio_username
}

resource "osc_secret" "miniopassword" {
  service_ids  = ["minio-minio", "encore", "eyevinn-encore-packager"]
  secret_name  = "${var.adpipeline_name}miniopassword"
  secret_value = var.minio_password
}

resource "osc_secret" "valkeypassword" {
  service_ids  = ["valkey-io-valkey"]
  secret_name  = "${var.adpipeline_name}valkeypassword"
  secret_value = var.valkey_password
}

resource "osc_secret" "token" {
  service_ids  = ["eyevinn-encore-packager", "eyevinn-ad-normalizer"]
  secret_name  = "${var.adpipeline_name}oscpat"
  secret_value = var.osc_pat
}


############################
# Resource: Minio storage
############################
resource "osc_minio_minio" "this" {
  name          = var.adpipeline_name
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
    environment = {
      AWS_ACCESS_KEY_ID     = var.minio_username
      AWS_SECRET_ACCESS_KEY = var.minio_password
    }
  }
}

############################
# Resource: Encore
############################
resource "osc_encore" "this" {
  name                 = var.adpipeline_name
  s3_access_key_id     = osc_minio_minio.this.root_user
  s3_secret_access_key = osc_minio_minio.this.root_password

  s3_endpoint = osc_minio_minio.this.instance_url #Use the URL from the minio instance created
  depends_on  = [null_resource.create_buckets, osc_minio_minio.this]
}

############################
# Resource: Valkey
############################

resource "osc_valkey_io_valkey" "this" {
  name     = var.adpipeline_name
  password = format("{{secrets.%s}}", osc_secret.valkeypassword.secret_name)
}

resource "osc_secret" "redis_url" {
  service_ids  = ["eyevinn-ad-normalizer", "eyevinn-encore-packager"]
  secret_name  = "${var.adpipeline_name}redisurl"
  secret_value = local.valkey_redis_url
  depends_on   = [osc_valkey_io_valkey.this]
}

############################
# Resource: Test AdServer
############################
resource "osc_eyevinn_test_adserver" "this" {
  name        = var.adpipeline_name
  mrss_origin = ""
}

############################
# Resource: Ad Normalizer
############################
resource "osc_eyevinn_ad_normalizer" "this" {
  name                 = var.adpipeline_name
  encore_url           = osc_encore.this.instance_url
  ad_server_url        = format("%s/api/v1/ads", osc_eyevinn_test_adserver.this.instance_url)
  output_bucket_url    = "s3://${var.encore_packager_bucket}"
  packaging_queue_name = var.encore_packager_queue
  jit_packaging        = false
  encore_profile       = "program"
  redis_url            = format("{{secrets.%s}}", osc_secret.redis_url.secret_name)
  asset_server_url     = "${osc_minio_minio.this.instance_url}/${var.encore_packager_bucket}"
  osc_access_token     = format("{{secrets.%s}}", osc_secret.token.secret_name)

  depends_on = [osc_eyevinn_test_adserver.this, osc_encore.this, osc_minio_minio.this]
}


############################
# Resource: Encore Packager
############################
resource "osc_eyevinn_encore_packager" "this" {
  name = var.adpipeline_name

  redis_url             = format("{{secrets.%s}}", osc_secret.redis_url.secret_name)
  aws_access_key_id     = osc_minio_minio.this.root_user
  aws_secret_access_key = osc_minio_minio.this.root_password
  output_folder         = format("s3://%s/%s/", var.encore_packager_bucket, var.encore_packager_output_folder)
  personal_access_token = format("{{secrets.%s}}", osc_secret.token.secret_name)
  callback_url          = osc_eyevinn_ad_normalizer.this.instance_url
  aws_region            = osc_encore.this.s3_region
  s3_endpoint_url       = osc_minio_minio.this.instance_url
  redis_queue           = var.encore_packager_queue

  depends_on = [osc_secret.redis_url, osc_minio_minio.this, osc_eyevinn_ad_normalizer.this]

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

## --- Test AdServer ---
output "testadserver_external_ip" {
  value = osc_eyevinn_test_adserver.this.external_ip
}
output "testadserver_external_port" {
  value = osc_eyevinn_test_adserver.this.external_port
}
output "testadserver_instance_url" {
  value = osc_eyevinn_test_adserver.this.instance_url
}
output "testadserver_service_id" {
  value = osc_eyevinn_test_adserver.this.service_id
}

## --- Ad Normalizer ---
output "adnormalizer_external_ip" {
  value = osc_eyevinn_ad_normalizer.this.external_ip
}
output "adnormalizer_external_port" {
  value = osc_eyevinn_ad_normalizer.this.external_port
}
output "adnormalizer_instance_url" {
  value = osc_eyevinn_ad_normalizer.this.instance_url
}
output "adnormalizer_service_id" {
  value = osc_eyevinn_ad_normalizer.this.service_id
}
