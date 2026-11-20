
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

