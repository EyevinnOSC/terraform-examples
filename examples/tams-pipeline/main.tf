terraform {
  required_version = ">= 1.6.0" # Compatible with Terraform >= 1.6.0 and OpenTofu >= 1.6.0
  required_providers {
    osc = {
      source  = "registry.terraform.io/EyevinnOSC/osc"
      version = "0.8.0" # v0.8.0 adds the required s3_bucket argument to osc_eyevinn_tams_gateway. Released 2026-06-18.
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
  description = "OSC environment (prod|stage|dev)"
}

variable "tams_name" {
  type        = string
  default     = "tams"
  description = "Instance name shared by the stack. Lower case letters and numbers only (OSC naming rule)."
}

variable "tams_bucket" {
  type        = string
  default     = "tams"
  description = "S3 bucket for media objects. Created in MinIO by this template; the gateway never creates buckets. Use a dot-free name (native AWS S3 virtual-hosted TLS)."
}

variable "minio_username" {
  type        = string
  sensitive   = true
  description = "MinIO root user. Supplied to the gateway as AWS_ACCESS_KEY_ID (MinIO speaks the S3 protocol)."
}

variable "minio_password" {
  type        = string
  sensitive   = true
  description = "MinIO root password. Supplied to the gateway as AWS_SECRET_ACCESS_KEY. Min 10 chars, lower + upper + digit (minio-minio pattern)."
}

variable "couchdb_password" {
  type        = string
  sensitive   = true
  description = "CouchDB admin password (the gateway's DB_PASSWORD)."
}

# No api_token variable: on OSC the ingress access gate authenticates callers via a
# Service Access Token (SAT), so the gateway runs without its own bearer token.
# (API_TOKEN is optional in the gateway, and ApiToken was removed from the
# eyevinn-tams-gateway catalog schema.) For a standalone, gate-less deployment you
# would set API_TOKEN out of band; this OSC Solution does not.

############################
# Provider
############################
provider "osc" {
  pat         = var.osc_pat
  environment = var.osc_environment
}

############################
# Secrets (created first; referenced by {{secrets.NAME}})
############################
resource "osc_secret" "miniousername" {
  service_ids  = ["minio-minio", "eyevinn-tams-gateway"]
  secret_name  = "${var.tams_name}miniousername"
  secret_value = var.minio_username
}

resource "osc_secret" "miniopassword" {
  service_ids  = ["minio-minio", "eyevinn-tams-gateway"]
  secret_name  = "${var.tams_name}miniopassword"
  secret_value = var.minio_password
}

resource "osc_secret" "couchdbpassword" {
  service_ids  = ["apache-couchdb", "eyevinn-tams-gateway"]
  secret_name  = "${var.tams_name}couchdbpassword"
  secret_value = var.couchdb_password
}

############################
# MinIO (S3 essence store)
############################
resource "osc_minio_minio" "this" {
  name          = var.tams_name
  root_user     = format("{{secrets.%s}}", osc_secret.miniousername.secret_name)
  root_password = format("{{secrets.%s}}", osc_secret.miniopassword.secret_name)
}

############################
# Bucket creation: the proven null_resource + local-exec pattern.
# The bucket name is a deploy input, so MinIO and CouchDB provision in parallel;
# the only hard ordering edge is "bucket ready before the gateway starts". The
# create_buckets.sh retry loop tolerates a freshly-started MinIO.
############################
resource "null_resource" "create_bucket" {
  depends_on = [osc_minio_minio.this]

  provisioner "local-exec" {
    command     = "${path.module}/create_buckets.sh ${osc_minio_minio.this.instance_url} ${var.tams_bucket}"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      AWS_ACCESS_KEY_ID     = var.minio_username
      AWS_SECRET_ACCESS_KEY = var.minio_password
    }
  }
}

############################
# CouchDB (segment/flow metadata index)
############################
resource "osc_apache_couchdb" "this" {
  name           = var.tams_name
  admin_password = format("{{secrets.%s}}", osc_secret.couchdbpassword.secret_name)
}

############################
# TAMS gateway (boots only after the bucket exists and CouchDB is reachable)
############################
resource "osc_eyevinn_tams_gateway" "this" {
  name                  = var.tams_name
  db_url                = osc_apache_couchdb.this.instance_url
  db_username           = "admin"
  db_password           = format("{{secrets.%s}}", osc_secret.couchdbpassword.secret_name)
  aws_access_key_id     = var.minio_username
  aws_secret_access_key = format("{{secrets.%s}}", osc_secret.miniopassword.secret_name)
  s3_endpoint_url       = osc_minio_minio.this.instance_url
  # s3_bucket is a REQUIRED argument as of provider v0.8.0 (2026-06-18).
  s3_bucket             = var.tams_bucket
  # No api_token: the OSC access gate authenticates via SAT (see the variables
  # section). ApiToken was removed from the eyevinn-tams-gateway catalog schema, so
  # the provider resource takes no token argument here.

  depends_on = [
    null_resource.create_bucket, # bucket must pre-exist; the gateway never creates it
    osc_apache_couchdb.this      # DB reachable for the gateway's startup auto-create
  ]
}

############################
# Outputs
############################
output "tams_gateway_url" {
  value = osc_eyevinn_tams_gateway.this.instance_url
}

output "minio_instance_url" {
  value = osc_minio_minio.this.instance_url
}

output "couchdb_instance_url" {
  value = osc_apache_couchdb.this.instance_url
}
