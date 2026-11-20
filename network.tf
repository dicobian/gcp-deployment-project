//VPC NETWORK
resource "google_compute_network" "vpc" {
  name                    = "my-network"
  auto_create_subnetworks = false
}

//SUBNETWORK indo
resource "google_compute_subnetwork" "subnetwork-indonesia" {
  name                     = "subnet-indonesia"
  region                   = "asia-southeast2"
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.10.1.0/24"
  private_ip_google_access = true

}

resource "google_compute_subnetwork" "subnetwork-singapura" {
  name                     = "subnet-singapura"
  region                   = "asia-southeast1"
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.10.2.0/24"
  private_ip_google_access = true
}

//FIREWALL FOR HEALTH CHECK
resource "google_compute_firewall" "firewall" {
  name    = "allow-health-check-laravel"
  network = google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "8080", "1000-2000"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  source_tags   = ["allow-health-check-laravel"]
  target_tags   = ["allow-health-check-laravel"]

}

//FIREWALL FOR SSH
resource "google_compute_firewall" "firewall-ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["allow-ssh-iap"]
}

//ROUTER INDONESIA
resource "google_compute_router" "indonesia-router" {
  name    = "indonesia-router"
  region  = "asia-southeast2"
  network = google_compute_network.vpc.id
}
// NAT INDONESIA
resource "google_compute_router_nat" "indonesia-nat" {
  name                               = "indonesia-nat"
  router                             = google_compute_router.indonesia-router.name
  region                             = google_compute_router.indonesia-router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
//ROUTER SINGAPURA
resource "google_compute_router" "singapura-router" {
  name    = "singapura-router"
  region  = "asia-southeast1"
  network = google_compute_network.vpc.id
}
// NAT SINGAPURA
resource "google_compute_router_nat" "singapura-nat" {
  name                               = "singapura-nat"
  router                             = google_compute_router.singapura-router.name
  region                             = google_compute_router.singapura-router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}


//PRIVATE SERCVICE ACCESS (for cloud sql private IP)
resource "google_compute_global_address" "psa_range" {
  name          = "tf-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]
  depends_on              = [google_compute_global_address.psa_range]
}
