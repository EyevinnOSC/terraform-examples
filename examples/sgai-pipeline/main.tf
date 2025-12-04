terraform {
  required_version = ">= 1.6.0"
  required_providers {
    osc = {
      source  = "EyevinnOSC/osc"
      version = "0.4.0"
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

variable "sgai_name" {
  type        = string
  default     = "mysgaipipeline"
  description = "Name of the ad-pipeline. Lower case letters and numbers only"
}

variable "minio_username" {
  type        = string
  sensitive   = true
  description = "Set the minio user name"
}

variable "minio_password" {
  type        = string
  sensitive   = true
  description = "Set the minio password"
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
  description = "Set the password for Valkey"
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

variable "sgai_ad_proxy_insertion_mode" {
  type        = string
  default     = "dynamic"
  description = "Insertion mode. One of [dynamic,static]"
}

variable "sgai_ad_proxy_source_origin_url" {
  type        = string
  default     = "https://somehost/playlist.m3u8"
  description = "The url to the oringal source stream (e.g. https://<some_host>/path/playlist.m3u8). Not required when using the hls test source"
}

variable "sgai_ad_proxy_vast_query_string" {
  type        = string
  default     = "/api/v1/vast?dur=[template.duration]&uid=[template.sessionId]&ps=[template.pod]&min=5&max=5"
  description = "Path and query template for VAST end-point. See docs for details"
}

variable "create_hls_test_source" {
  type        = bool
  default     = false
  description = "In case you do not have a suitable live stream of your own to use, the solution can automatically create a live test source via Eyevinn OSC. One of [true,false]"
}

variable "create_adserver_ui" {
  type        = bool
  default     = false
  description = "In case you want the solution to also create a frontend for the AdServer. One of [true,false]"
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
  secret_name  = "${var.sgai_name}miniousername"
  secret_value = var.minio_username
}

resource "osc_secret" "miniopassword" {
  service_ids  = ["minio-minio", "encore", "eyevinn-encore-packager"]
  secret_name  = "${var.sgai_name}miniopassword"
  secret_value = var.minio_password
}

resource "osc_secret" "valkeypassword" {
  service_ids  = ["valkey-io-valkey"]
  secret_name  = "${var.sgai_name}valkeypassword"
  secret_value = var.valkey_password
}

resource "osc_secret" "token" {
  service_ids  = ["eyevinn-encore-packager", "eyevinn-ad-normalizer"]
  secret_name  = "${var.sgai_name}oscpat"
  secret_value = var.osc_pat
}


############################
# Resource: Minio storage
############################
resource "osc_minio_minio" "this" {
  name          = var.sgai_name
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

## Set public access to the packaged files so that plyaers can access the segments
resource "null_resource" "set_public_access" {
  depends_on = [null_resource.create_buckets]
  provisioner "local-exec" {
    command     = "${path.module}/allow_public_access_to_ads.sh ${osc_minio_minio.this.instance_url} ${var.encore_packager_bucket}"
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
  name                 = var.sgai_name
  s3_access_key_id     = osc_minio_minio.this.root_user
  s3_secret_access_key = osc_minio_minio.this.root_password

  s3_endpoint = osc_minio_minio.this.instance_url #Use the URL from the minio instance created
  depends_on  = [null_resource.create_buckets, osc_minio_minio.this]
}

############################
# Resource: Valkey
############################

resource "osc_valkey_io_valkey" "this" {
  name     = var.sgai_name
  password = format("{{secrets.%s}}", osc_secret.valkeypassword.secret_name)
}

resource "osc_secret" "redis_url" {
  service_ids  = ["eyevinn-ad-normalizer", "eyevinn-encore-packager"]
  secret_name  = "${var.sgai_name}redisurl"
  secret_value = local.valkey_redis_url
  depends_on   = [osc_valkey_io_valkey.this]
}

############################
# Resource: Test AdServer
############################
resource "osc_eyevinn_test_adserver" "this" {
  name        = var.sgai_name
  mrss_origin = ""
}

############################
# Resource: Ad Normalizer
############################
resource "osc_eyevinn_ad_normalizer" "this" {
  name                 = var.sgai_name
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
  name = var.sgai_name

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
# Resource: SGAI AD-Proxy
############################
resource "osc_eyevinn_sgai_ad_proxy" "this" {
  depends_on = [osc_eyevinn_docker_testsrc_hls_live.this]

  insertion_mode = var.sgai_ad_proxy_insertion_mode
  name           = var.sgai_name
  origin_url     = var.create_hls_test_source ? format("%s/loop/master.m3u8", osc_eyevinn_docker_testsrc_hls_live.this[0].instance_url) : var.sgai_ad_proxy_source_origin_url
  vast_endpoint  = "${osc_eyevinn_ad_normalizer.this.instance_url}${var.sgai_ad_proxy_vast_query_string}"
}

############################
# Resource: Live test stream
############################
resource "osc_eyevinn_docker_testsrc_hls_live" "this" {
  count = var.create_hls_test_source ? 1 : 0
  name  = var.sgai_name
}

resource "osc_ablindberg_adserver_frontend" "this" {
  count = var.create_adserver_ui ? 1 : 0
  name  = var.sgai_name
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

## --- SGAI Ad Proxy ---
output "sgaiadproxy_external_ip" {
  value = osc_eyevinn_sgai_ad_proxy.this.external_ip
}
output "sgaiadproxy_external_port" {
  value = osc_eyevinn_sgai_ad_proxy.this.external_port
}
output "sgaiadproxy_instance_url" {
  value = osc_eyevinn_sgai_ad_proxy.this.instance_url
}
output "sgaiadproxy_service_id" {
  value = osc_eyevinn_sgai_ad_proxy.this.service_id
}

## --- HLS Test Source ---
output "hlstestsource_external_ip" {
  value = osc_eyevinn_docker_testsrc_hls_live.this[*].external_ip
}
output "hlstestsource_external_port" {
  value = osc_eyevinn_docker_testsrc_hls_live.this[*].external_port
}
output "hlstestsource_instance_url" {
  value = osc_eyevinn_docker_testsrc_hls_live.this[*].instance_url
}
output "hlstestsource_service_id" {
  value = osc_eyevinn_docker_testsrc_hls_live.this[*].service_id
}

## --- Test AdServer UI ---
output "testadserverui_external_ip" {
  value = osc_ablindberg_adserver_frontend.this[*].external_ip
}
output "testadserverui_external_port" {
  value = osc_ablindberg_adserver_frontend.this[*].external_port
}
output "testadserverui_instance_url" {
  value = osc_ablindberg_adserver_frontend.this[*].instance_url
}
output "testadserverui_service_id" {
  value = osc_ablindberg_adserver_frontend.this[*].service_id
}
