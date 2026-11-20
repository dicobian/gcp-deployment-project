
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
