# -----------------------------------------------------------------------------
# Secret Manager secrets and random password generation
# -----------------------------------------------------------------------------

# --- Random Passwords --------------------------------------------------------

resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#%()-_=+"
}

resource "random_password" "admin_password" {
  length           = 24
  special          = true
  override_special = "!#%()-_=+"
}

# --- Secret Manager Secrets --------------------------------------------------

resource "google_secret_manager_secret" "db_password" {
  secret_id = "espocrm-db-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret" "admin_password" {
  secret_id = "espocrm-admin-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret" "oauth_client_secret" {
  secret_id = "espocrm-oauth-client-secret"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

# --- Secret Versions ---------------------------------------------------------

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "google_secret_manager_secret_version" "admin_password" {
  secret      = google_secret_manager_secret.admin_password.id
  secret_data = random_password.admin_password.result
}

resource "google_secret_manager_secret_version" "oauth_client_secret" {
  count       = var.oauth_client_secret != "" ? 1 : 0
  secret      = google_secret_manager_secret.oauth_client_secret.id
  secret_data = var.oauth_client_secret
}
