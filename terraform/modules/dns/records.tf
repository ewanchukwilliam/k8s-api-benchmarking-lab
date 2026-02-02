# DNS Records - Separate from main.tf for clarity

variable "create_app_record" {
  description = "Whether to create the A/CNAME record for the app"
  type        = bool
  default     = false
}

variable "app_load_balancer_hostname" {
  description = "Load balancer hostname to point DNS at"
  type        = string
  default     = ""
}

variable "app_load_balancer_zone_id" {
  description = "Load balancer hosted zone ID (for alias records)"
  type        = string
  default     = ""
}

# Application DNS record (points to load balancer)
# Using alias record for AWS load balancers (no TTL charges, better performance)
resource "aws_route53_record" "app" {
  count   = var.create_app_record && var.app_load_balancer_hostname != "" ? 1 : 0
  zone_id = local.zone_id
  name    = local.full_domain
  type    = "A"

  alias {
    name                   = var.app_load_balancer_hostname
    zone_id                = var.app_load_balancer_zone_id
    evaluate_target_health = true
  }
}

# Alternative: CNAME record (if not using alias)
resource "aws_route53_record" "app_cname" {
  count   = var.create_app_record && var.app_load_balancer_hostname != "" && var.app_load_balancer_zone_id == "" ? 1 : 0
  zone_id = local.zone_id
  name    = local.full_domain
  type    = "CNAME"
  ttl     = 60
  records = [var.app_load_balancer_hostname]
}

output "app_fqdn" {
  description = "Fully qualified domain name for the application"
  value       = var.create_app_record ? local.full_domain : ""
}
