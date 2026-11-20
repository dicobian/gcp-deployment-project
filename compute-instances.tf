
// IMAGE FOR INSTANCE TEMPLATE
# data "google_compute_image" "laravel-image" {
#   name    = "laravel-image2"
#   project = var.project_id2
# }
// IMAGE FOR INSTANCE TEMPLATE CREATED FROM INSTANCE DISK
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
