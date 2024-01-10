provider "aws" {
  region = "us-east-1" # or your preferred region
}

terraform {
  backend "s3" {
    bucket         = "drj-terraform-state-bucket"
    key            = "marketplacepro-docs/production/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-lock-table"
    encrypt        = true
  }
}

data "aws_route53_zone" "selected" {
  name         = "${var.tld}."
  private_zone = false
}

resource "aws_s3_bucket" "docusaurus_bucket" {
  bucket = var.bucket_name
}

# Create an Origin Access Identity for CloudFront
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${aws_s3_bucket.docusaurus_bucket.bucket}"
}

# Update the S3 bucket policy to allow access from CloudFront OAI
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.docusaurus_bucket.bucket
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "s3:GetObject",
        Effect   = "Allow",
        Resource = "arn:aws:s3:::${aws_s3_bucket.docusaurus_bucket.bucket}/*",
        Principal = {
          AWS = "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${aws_cloudfront_origin_access_identity.oai.id}"
        }
      }
    ]
  })
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

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.ssl_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [aws_acm_certificate_validation.cert_validation, aws_s3_bucket_policy.bucket_policy]

  origin {
    domain_name = aws_s3_bucket.docusaurus_bucket.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.docusaurus_bucket.id}"

    # Use the OAI for this origin
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
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
