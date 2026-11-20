//VPC NETWORK
resource "google_compute_network" "vpc" {
  name                    = "my-network"
  auto_create_subnetworks = false
}

//SUBNETWORK indo
resource "google_compute_subnetwork" "subnetwork-indonesia" {
  name          = "subnet-indonesia"
  region        = "asia-southeast2"
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.10.1.0/24"

}

resource "google_compute_subnetwork" "subnetwork-singapura" {
  name          = "subnet-singapura"
  region        = "asia-southeast1"
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.10.2.0/24"
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

//IAM SERVICE ACCOUNT
resource "google_service_account" "vm" {
  account_id   = "laravel-vm-account"
  display_name = "Service account VM Laravel"
}

//IAM BUCKET
resource "google_storage_bucket_iam_member" "vm_bucket" {
  bucket = google_storage_bucket.app.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vm.email}"
}
//IAM BUCKET, ADD ROLE TOKEN CREATOR INTO SERVICE ACCOUNT
resource "google_service_account_iam_member" "vm_token_creator" {
  service_account_id = google_service_account.vm.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.vm.email}"
}

//IAM CLOUD SQL, ADD ROLE INTO SERVICE ACCOUNT
resource "google_project_iam_member" "vm_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.vm.email}"
}


//IAM SECRET MANAGER 
resource "google_secret_manager_secret_iam_member" "secret_access" {
  secret_id = google_secret_manager_secret.db_password_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}

//BUCKET STORAGE
resource "google_storage_bucket" "app" {
  name                        = "${var.project_id}-laravel"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
}

//CLOUD SQL INSTANCE
resource "google_sql_database_instance" "laravel-sql-instance" {
  name                = "laravel-sql-instance"
  region              = "asia-southeast2"
  database_version    = "POSTGRES_18"
  deletion_protection = false

  settings {
    edition           = "ENTERPRISE"
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }

    backup_configuration {
      enabled = false
    }
  }

  depends_on = [google_compute_network.vpc, google_compute_subnetwork.subnetwork-indonesia, google_service_networking_connection.psa]
}

//CLOUD SQL USER & DATABASE
//random password 
resource "random_password" "db" {
  length  = 24
  special = false
}
//CREATE DATABASE
resource "google_sql_database" "laravel" {
  name     = "laravel"
  instance = google_sql_database_instance.laravel-sql-instance.name
}
//CREATE USER 
resource "google_sql_user" "laravel" {
  name     = "laravel"
  instance = google_sql_database_instance.laravel-sql-instance.name
  password = random_password.db.result

  deletion_policy = "ABANDON"
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}

output "db_connection_name" {
  value = google_sql_database_instance.laravel-sql-instance.connection_name
}

//SECRET MANAGER 
resource "google_secret_manager_secret" "db_password_secret" {
  secret_id = "laravel_db_password"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis["secretmanager.googleapis.com"]]
}
resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password_secret.id
  secret_data = random_password.db.result
}



// IMAGE FOR INSTANCE TEMPLATE
# data "google_compute_image" "laravel-image" {
#   name    = "laravel-image2"
#   project = var.project_id2
# }

resource "google_compute_image" "laravel-image" {
  name        = "laravel-image"
  source_disk = "projects/belajar-project-terraform/zones/asia-southeast2-b/disks/laravel-model3"
  lifecycle {
    prevent_destroy = false
  }
}

// INSTANCE TEMPLATE REGIONAL INDONESIA 
resource "google_compute_region_instance_template" "laravel-instance-template-indonesia" {
  name_prefix  = "laravel-indonesia"
  machine_type = "e2-small"
  tags         = ["allow-health-check-laravel", "allow-ssh-iap"]
  region       = "asia-southeast2"

  disk {
    source_image = google_compute_image.laravel-image.self_link
    boot         = true
    auto_delete  = true
    disk_size_gb = 10
  }
  network_interface {
    subnetwork = google_compute_subnetwork.subnetwork-indonesia.id
  }
  scheduling {
    provisioning_model          = "SPOT"
    preemptible                 = true
    automatic_restart           = false
    on_host_maintenance         = "TERMINATE"
    instance_termination_action = "STOP"
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -euo pipefail

    SECRET="laravel_db_password"
    PROJECT="belajar-project-terraform"
    BUCKET="belajar-project-terraform-laravel"
    ENV_FILE="/var/www/school-app/.env"  
    SQL_PROXY_FILE="/etc/systemd/system/cloud-sql-proxy.service"
    CONNECTION_NAME="belajar-project-terraform:asia-southeast2:laravel-sql-instance"
    PASSWORD=$(gcloud secrets versions access latest --secret="$SECRET" --project="$PROJECT")
    USERNAME="laravel"

    sed -i \
    -e "s~^[[:space:]]*DB_PASSWORD=.*~DB_PASSWORD=$${PASSWORD}~" \
    -e "s~^[[:space:]]*DB_USERNAME=.*~DB_USERNAME=$${USERNAME}~" \
    -e "s~^[[:space:]]*GOOGLE_CLOUD_PROJECT_ID=.*~GOOGLE_CLOUD_PROJECT_ID=$${PROJECT}~" \
    -e "s~^[[:space:]]*GOOGLE_CLOUD_STORAGE_BUCKET=.*~GOOGLE_CLOUD_STORAGE_BUCKET=$${BUCKET}~" \
    "$ENV_FILE"

    sed -i "s~^ExecStart=/usr/local/bin/cloud-sql-proxy.*~ExecStart=/usr/local/bin/cloud-sql-proxy --private-ip $${CONNECTION_NAME} --port=5432~" "$SQL_PROXY_FILE"

    cd /var/www/school-app
    php artisan config:clear
    systemctl daemon-reload
    systemctl restart cloud-sql-proxy
    systemctl restart apache2

  EOF
}

//INSTANCE TEMPLATE REGIONAL SINGAPURA

resource "google_compute_region_instance_template" "laravel-instance-template-singapura" {
  name_prefix  = "laravel-singapura"
  machine_type = "e2-small"
  tags         = ["allow-health-check-laravel", "allow-ssh-iap"]
  region       = "asia-southeast1"

  disk {
    source_image = google_compute_image.laravel-image.self_link
    boot         = true
    auto_delete  = true
    disk_size_gb = 10
  }
  network_interface {
    subnetwork = google_compute_subnetwork.subnetwork-singapura.id
  }
  scheduling {
    provisioning_model          = "SPOT"
    preemptible                 = true
    automatic_restart           = false
    on_host_maintenance         = "TERMINATE"
    instance_termination_action = "STOP"
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -euo pipefail

    SECRET="laravel_db_password"
    PROJECT="belajar-project-terraform"
    BUCKET="belajar-project-terraform-laravel"
    ENV_FILE="/var/www/school-app/.env"  
    SQL_PROXY_FILE="/etc/systemd/system/cloud-sql-proxy.service"
    CONNECTION_NAME="belajar-project-terraform:asia-southeast2:laravel-sql-instance"
    PASSWORD=$(gcloud secrets versions access latest --secret="$SECRET" --project="$PROJECT")
    USERNAME="laravel"

    sed -i \
    -e "s~^[[:space:]]*DB_PASSWORD=.*~DB_PASSWORD=$${PASSWORD}~" \
    -e "s~^[[:space:]]*DB_USERNAME=.*~DB_USERNAME=$${USERNAME}~" \
    -e "s~^[[:space:]]*GOOGLE_CLOUD_PROJECT_ID=.*~GOOGLE_CLOUD_PROJECT_ID=$${PROJECT}~" \
    -e "s~^[[:space:]]*GOOGLE_CLOUD_STORAGE_BUCKET=.*~GOOGLE_CLOUD_STORAGE_BUCKET=$${BUCKET}~" \
    "$ENV_FILE"

    sed -i "s~^ExecStart=/usr/local/bin/cloud-sql-proxy.*~ExecStart=/usr/local/bin/cloud-sql-proxy --private-ip $${CONNECTION_NAME} --port=5432~" "$SQL_PROXY_FILE"

    cd /var/www/school-app
    php artisan config:clear
    systemctl daemon-reload
    systemctl restart cloud-sql-proxy
    systemctl restart apache2

  EOF
}

//HEALTH CHECK
resource "google_compute_health_check" "laravel-health-check" {
  name                = "laravel-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/up"
  }
}

//INSTANCE GROUP INDONESIA
resource "google_compute_region_instance_group_manager" "laravel-indonesia" {
  name                      = "laravel-indonesia"
  base_instance_name        = "laravel-indonesia"
  region                    = "asia-southeast2"
  distribution_policy_zones = ["asia-southeast2-a", "asia-southeast2-b", "asia-southeast2-c"]

  version {
    instance_template = google_compute_region_instance_template.laravel-instance-template-indonesia.self_link
  }

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.laravel-health-check.id
    initial_delay_sec = 300
  }

  update_policy {
    type                           = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed                = 3
    max_unavailable_fixed          = 0
  }

  depends_on = [
    google_compute_router_nat.indonesia-nat,
    google_compute_firewall.firewall,
    google_secret_manager_secret_version.db_password_version,
    google_secret_manager_secret_iam_member.secret_access,
    google_project_iam_member.vm_sql,
    google_sql_database.laravel,
    google_sql_user.laravel,
  ]
}

//INSTANCE GROUP INDONESIA AUTOSCALER
resource "google_compute_region_autoscaler" "laravel-group-autoscaler" {
  name   = "laravel-group-autoscaler"
  region = "asia-southeast2"
  target = google_compute_region_instance_group_manager.laravel-indonesia.id

  autoscaling_policy {
    min_replicas    = 1
    max_replicas    = 3
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }
}

//INSTANCE GROUP SINGAPURA
resource "google_compute_region_instance_group_manager" "laravel-singapura" {
  name                      = "laravel-singapura"
  base_instance_name        = "laravel-singapura"
  region                    = "asia-southeast1"
  distribution_policy_zones = ["asia-southeast1-a", "asia-southeast1-b", "asia-southeast1-c"]

  version {
    instance_template = google_compute_region_instance_template.laravel-instance-template-singapura.self_link
  }

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.laravel-health-check.id
    initial_delay_sec = 300
  }

  update_policy {
    type                           = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed                = 3
    max_unavailable_fixed          = 0
  }

  depends_on = [
    google_compute_router_nat.singapura-nat,
    google_compute_firewall.firewall,
    google_secret_manager_secret_version.db_password_version,
    google_secret_manager_secret_iam_member.secret_access,
    google_project_iam_member.vm_sql,
    google_sql_database.laravel,
    google_sql_user.laravel,
  ]
}

//INSTANCE GROUP SINGAPURA AUTOSCALER
resource "google_compute_region_autoscaler" "laravel-group-autoscaler-singapura" {
  name   = "laravel-group-autoscaler-singapura"
  region = "asia-southeast1"
  target = google_compute_region_instance_group_manager.laravel-singapura.id

  autoscaling_policy {
    min_replicas    = 1
    max_replicas    = 3
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }
}

//==================
//LOAD BALANCER 
//==================
// STATIC GLOBAL IP / ANYCAST -> FORWARDING RULE -> TARGET PROXY -> URL MAP -> BACKEND SERVICE -> INSTANCE SERVER 

//ANYCAST, STATIC GLOBAL IP
resource "google_compute_global_address" "lb_ip" {
  name = "laravel-lb-ip"
}

//BACKEND SERVICE 
resource "google_compute_backend_service" "laravel" {
  name                  = "laravel-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.laravel-health-check.id]

  //backend indonesia
  backend {
    group           = google_compute_region_instance_group_manager.laravel-indonesia.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }
  //backend singapura
  backend {
    group           = google_compute_region_instance_group_manager.laravel-singapura.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }

}
//URL MAP
resource "google_compute_url_map" "laravel" {
  name            = "laravel-load-balancer"
  default_service = google_compute_backend_service.laravel.id
}
//TARGET PROXY
resource "google_compute_target_http_proxy" "laravel" {
  name    = "laravel-http-proxy"
  url_map = google_compute_url_map.laravel.id
}

//FORWARDING RULE
resource "google_compute_global_forwarding_rule" "laravel" {
  name                  = "laravel-forwarding-rule"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.laravel.id
  ip_address            = google_compute_global_address.lb_ip.id
}


output "lb-ip" {
  value = google_compute_global_address.lb_ip.address
}
