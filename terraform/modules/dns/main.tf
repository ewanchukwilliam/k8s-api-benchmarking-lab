# DNS Module - Route53 Hosted Zone, ACM Certificate, DNS Records

variable "domain" {
  description = "Root domain name (e.g., codeseeker.dev)"
  type        = string
}

variable "subdomain" {
  description = "Subdomain for the application (e.g., api)"
  type        = string
  default     = "api"
}

variable "create_hosted_zone" {
  description = "Whether to create a new hosted zone or use existing"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

locals {
  full_domain = "${var.subdomain}.${var.domain}"
}

# Look up existing hosted zone or create new one
data "aws_route53_zone" "existing" {
  count = var.create_hosted_zone ? 0 : 1
  name  = var.domain
}

resource "aws_route53_zone" "new" {
  count = var.create_hosted_zone ? 1 : 0
  name  = var.domain

  tags = merge(var.tags, {
    Name = var.domain
  })
}

locals {
  zone_id = var.create_hosted_zone ? aws_route53_zone.new[0].zone_id : data.aws_route53_zone.existing[0].zone_id
}

# ACM Certificate
resource "aws_acm_certificate" "main" {
  domain_name       = local.full_domain
  validation_method = "DNS"

  tags = merge(var.tags, {
    Name = local.full_domain
  })

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation record for ACM
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Outputs
output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.zone_id
}

output "zone_name_servers" {
  description = "Name servers for the hosted zone (update at your registrar)"
  value       = var.create_hosted_zone ? aws_route53_zone.new[0].name_servers : data.aws_route53_zone.existing[0].name_servers
}

output "certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = aws_acm_certificate_validation.main.certificate_arn
}

output "domain" {
  description = "Full domain name"
  value       = local.full_domain
}
