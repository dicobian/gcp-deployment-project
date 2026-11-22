
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
