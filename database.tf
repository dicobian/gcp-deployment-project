
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
