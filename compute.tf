# -----------------------------------------------------------------------------
# GCE instance running EspoCRM via Docker Compose
# Requirements: 6.1, 6.2, 5.4
# -----------------------------------------------------------------------------

resource "google_compute_instance" "espocrm" {
  name         = "espocrm"
  machine_type = "e2-small"
  zone         = var.zone
  tags         = ["espocrm"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.espocrm.id

    access_config {
      nat_ip = google_compute_address.espocrm.address
    }
  }

  service_account {
    email  = google_service_account.espocrm.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tpl", {
    db_host         = google_sql_database_instance.espocrm.private_ip_address
    db_name         = google_sql_database.espocrm.name
    db_user         = google_sql_user.espocrm.name
    project_id      = var.project_id
    region          = var.region
    domain          = var.domain
    oauth_client_id = var.oauth_client_id
  })

  depends_on = [
    google_sql_database_instance.espocrm,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_version.admin_password,
    google_project_iam_member.espocrm_secret_accessor,
    google_project_iam_member.espocrm_log_writer,
    google_project_iam_member.espocrm_metric_writer,
    google_project_iam_member.espocrm_vertex_ai_user,
    google_project_iam_member.espocrm_sa_key_creator,
    google_project_service.aiplatform,
    google_project_service.iam,
    google_compute_firewall.espocrm_allow_http_https,
    google_compute_firewall.espocrm_allow_ssh,
  ]
}
