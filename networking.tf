# Networking resources for EspoCRM GCP deployment
# VPC, subnet, static IP, firewall rules, and private services access

# --- VPC and Subnet ---

resource "google_compute_network" "espocrm" {
  name                    = "espocrm-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "espocrm" {
  name                     = "espocrm-subnet"
  ip_cidr_range            = "10.0.1.0/24"
  region                   = var.region
  network                  = google_compute_network.espocrm.id
  private_ip_google_access = true

  depends_on = [google_project_service.compute]
}

# --- Static External IP ---

resource "google_compute_address" "espocrm" {
  name         = "espocrm"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  depends_on = [google_project_service.compute]
}

# --- Firewall Rules ---

resource "google_compute_firewall" "espocrm_allow_http_https" {
  name    = "espocrm-allow-http-https"
  network = google_compute_network.espocrm.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["espocrm"]
}

resource "google_compute_firewall" "espocrm_allow_ssh" {
  name    = "espocrm-allow-ssh"
  network = google_compute_network.espocrm.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  direction     = "INGRESS"
  source_ranges = var.ssh_source_ranges
  target_tags   = ["espocrm"]
}

resource "google_compute_firewall" "espocrm_deny_all" {
  name    = "espocrm-deny-all"
  network = google_compute_network.espocrm.name

  deny {
    protocol = "all"
  }

  direction     = "INGRESS"
  priority      = 65534
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["espocrm"]
}

# --- Private Services Access ---

resource "google_compute_global_address" "private_services" {
  name          = "espocrm-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.espocrm.id

  depends_on = [google_project_service.servicenetworking]
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.espocrm.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]

  depends_on = [google_project_service.servicenetworking]
}
