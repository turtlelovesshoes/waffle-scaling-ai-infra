data "aws_route53_zone" "main" {
  name         = "designcodemonkey.space."
  private_zone = false
}

resource "aws_acm_certificate" "argocd" {
  domain_name               = "argocd.designcodemonkey.space"
  validation_method         = "DNS"
  subject_alternative_names = ["*.designcodemonkey.space"]

  tags = {
    Name        = "argocd.designcodemonkey.space"
    Environment = "dev"
  }
}

resource "aws_route53_record" "argocd_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.argocd.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "argocd" {
  certificate_arn         = aws_acm_certificate.argocd.arn
  validation_record_fqdns = [for record in aws_route53_record.argocd_cert_validation : record.fqdn]
}
## TODO: Create a variable here to reference the cert in main in the helm chart resource
