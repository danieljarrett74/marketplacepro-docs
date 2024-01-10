provider "aws" {
    region = "us-east-1" # or your preferred region
}

data "aws_route53_zone" "selected" {
    name         = "${var.tld}."
    private_zone = false
}

resource "aws_s3_bucket" "docusaurus_bucket" {
    bucket = var.bucket_name
}

resource "aws_route53_record" "doc_record" {
    zone_id = data.aws_route53_zone.selected.zone_id
    name    = "${var.subdomain}.${var.tld}"
    type    = "A"

    alias {
        name                   = aws_cloudfront_distribution.s3_distribution.domain_name
        zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
        evaluate_target_health = true
    }
}

resource "aws_acm_certificate" "ssl_cert" {
  domain_name       = "${var.subdomain}.${var.tld}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Add DNS validation record for the ACM certificate
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ssl_cert.domain_validation_options : dvo.domain_name => {
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
  zone_id         = data.aws_route53_zone.selected.zone_id
}

# Update ACM certificate to depend on the validation record
resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn = aws_acm_certificate.ssl_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "s3_distribution" {

        depends_on = [aws_acm_certificate_validation.cert_validation]

        origin {
                domain_name = aws_s3_bucket.docusaurus_bucket.bucket_regional_domain_name
                origin_id   = "S3-${aws_s3_bucket.docusaurus_bucket.id}"
        }

        enabled             = true
        default_root_object = "index.html"

        default_cache_behavior {
                viewer_protocol_policy = "redirect-to-https"
                allowed_methods        = ["GET", "HEAD"]
                cached_methods         = ["GET", "HEAD"]
                target_origin_id       = "S3-${aws_s3_bucket.docusaurus_bucket.id}"
                
                forwarded_values {
                        query_string = false
                        cookies {
                                forward = "none"
                        }
                }
        }

        viewer_certificate {
                acm_certificate_arn = aws_acm_certificate.ssl_cert.arn
                ssl_support_method  = "sni-only"
        }

        restrictions {
                geo_restriction {
                        restriction_type = "whitelist"
                        locations        = ["US"]
                }
        }
}
