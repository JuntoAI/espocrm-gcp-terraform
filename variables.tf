variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "your-gcp-project-id"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCE instance zone"
  type        = string
  default     = "us-central1-a"
}

variable "domain" {
  description = "Domain for TLS and site URL"
  type        = string
  default     = "crm.example.com"
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-f1-micro"
}

variable "db_backup_start_time" {
  description = "Daily backup window start (UTC)"
  type        = string
  default     = "03:00"
}

variable "deletion_protection" {
  description = "Cloud SQL deletion protection"
  type        = bool
  default     = true
}

variable "oauth_client_id" {
  description = "Google OAuth 2.0 client ID"
  type        = string
  default     = ""
}

variable "oauth_client_secret" {
  description = "Google OAuth 2.0 client secret"
  type        = string
  default     = ""
  sensitive   = true
}


