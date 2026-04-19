# -----------------------------------------------------------------------------
# Cloud SQL MySQL instance, database, and user
# Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.7
# -----------------------------------------------------------------------------

resource "google_sql_database_instance" "espocrm" {
  name                = "espocrm"
  database_version    = "MYSQL_8_0"
  region              = var.region
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.espocrm.id
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.db_backup_start_time
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 7
      }
    }
  }

  depends_on = [
    google_service_networking_connection.private_services,
    google_project_service.sqladmin,
  ]
}

resource "google_sql_database" "espocrm" {
  name      = "espocrm"
  instance  = google_sql_database_instance.espocrm.name
  charset   = "utf8mb4"
  collation = "utf8mb4_unicode_ci"
}

resource "google_sql_user" "espocrm" {
  name     = "espocrm"
  instance = google_sql_database_instance.espocrm.name
  password = random_password.db_password.result
}
