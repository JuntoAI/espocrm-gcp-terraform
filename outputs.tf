output "static_ip" {
  description = "Static external IP address for DNS A record configuration"
  value       = google_compute_address.espocrm.address
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL instance connection name for debugging and Cloud SQL Proxy"
  value       = google_sql_database_instance.espocrm.connection_name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP address for verification"
  value       = google_sql_database_instance.espocrm.private_ip_address
}

output "instance_name" {
  description = "GCE instance name for SSH access via gcloud compute ssh"
  value       = google_compute_instance.espocrm.name
}

output "instance_zone" {
  description = "GCE instance zone for SSH access via gcloud compute ssh"
  value       = google_compute_instance.espocrm.zone
}

output "application_url" {
  description = "EspoCRM application URL"
  value       = "https://${var.domain}"
}
