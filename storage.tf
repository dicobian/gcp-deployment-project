
//BUCKET STORAGE
resource "google_storage_bucket" "app" {
  name                        = "${var.project_id}-laravel"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
}
