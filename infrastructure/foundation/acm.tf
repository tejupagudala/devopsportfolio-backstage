
# ==========================================
# Backstage ACM Certificate
# DNS managed externally by GoDaddy
# ==========================================

resource "aws_acm_certificate" "backstage" {
  domain_name = "idp.thedevopsportfolio.online"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "backstage-idp-certificate"
  }
}

output "backstage_acm_certificate_arn" {
  value = aws_acm_certificate.backstage.arn
}

output "backstage_acm_dns_validation" {
  value = [
    for option in aws_acm_certificate.backstage.domain_validation_options : {
      name  = option.resource_record_name
      type  = option.resource_record_type
      value = option.resource_record_value
    }
  ]
}
