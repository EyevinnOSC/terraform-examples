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

variable "wordpress_name" {
  type        = string
  default     = "mywordpress"
  description = "Name of the WordPress solution. Lower case letters and numbers only"
}

variable "db_admin_password" {
  type        = string
  sensitive   = true
  description = "MariaDB admin password"
}

variable "db_username" {
  type        = string
  default     = "wpuser"
  description = "MariaDB user name"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "MariaDB user password"
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

resource "osc_secret" "dbadminpwd" {
  service_ids  = ["linuxserver-docker-mariadb"]
  secret_name  = "${var.wordpress_name}dbadminpwd"
  secret_value = var.db_admin_password
}

resource "osc_secret" "dbusername" {
  service_ids  = ["linuxserver-docker-mariadb", "wordpress-wordpress"]
  secret_name  = "${var.wordpress_name}dbusername"
  secret_value = var.db_username
}

resource "osc_secret" "dbuserpwd" {
  service_ids  = ["linuxserver-docker-mariadb", "wordpress-wordpress"]
  secret_name  = "${var.wordpress_name}dbuserpwd"
  secret_value = var.db_password
}

############################
# Resource: MariaDB Database
############################
resource "osc_linuxserver_docker_mariadb" "this" {
  name                  = var.wordpress_name
  root_password         = format("{{secrets.%s}}", osc_secret.dbadminpwd.secret_name)
  database              = "wordpress"
  user                  = format("{{secrets.%s}}", osc_secret.dbusername.secret_name)
  password              = format("{{secrets.%s}}", osc_secret.dbuserpwd.secret_name)
}

############################
# Resource: Wordpress
############################
resource "osc_wordpress_wordpress" "this" {
  name            = var.wordpress_name
  db_host         = format("%s:%d", osc_linuxserver_docker_mariadb.this.external_ip, osc_linuxserver_docker_mariadb.this.external_port)
  db_name         = "wordpress"
  db_user         = format("{{secrets.%s}}", osc_secret.dbusername.secret_name)
  db_password     = format("{{secrets.%s}}", osc_secret.dbuserpwd.secret_name)
  depends_on      = [osc_linuxserver_docker_mariadb.this]
}

############################
# Outputs
############################
  
## --- Database ---
output "DB_external_ip" {
  value = osc_linuxserver_docker_mariadb.this.external_ip
}
output "DB_external_port" {
  value = osc_linuxserver_docker_mariadb.this.external_port
}
output "DB_instance_url" {
  value = osc_linuxserver_docker_mariadb.this.instance_url
}
output "DB_service_id" {
  value = osc_linuxserver_docker_mariadb.this.service_id
}

## --- WordPress ---
output "WP_instance_url" {
  value = osc_wordpress_wordpress.this.instance_url
}
