# Service account for the EspoCRM GCE instance (least-privilege)
resource "google_service_account" "espocrm" {
  account_id   = "espocrm-instance-sa"
  display_name = "EspoCRM Instance Service Account"
}

# Secret Manager read-only access — allows startup script to fetch credentials
resource "google_project_iam_member" "espocrm_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.espocrm.email}"
}

# Cloud Logging write access — allows instance to ship logs
resource "google_project_iam_member" "espocrm_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.espocrm.email}"
}

# Cloud Monitoring write access — allows instance to export metrics
resource "google_project_iam_member" "espocrm_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.espocrm.email}"
}

# Vertex AI access — allows AI Backend to call Gemini via Vertex AI
resource "google_project_iam_member" "espocrm_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.espocrm.email}"
}

# Service Account Key Creator — allows startup script to generate a key
# for the AI Backend container (which can't reach the metadata server)
resource "google_project_iam_member" "espocrm_sa_key_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountKeyAdmin"
  member  = "serviceAccount:${google_service_account.espocrm.email}"
}
