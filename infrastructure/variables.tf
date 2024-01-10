variable "tld" {
    default = "myshopifyapp.xyz"
  description = "The top-level domain"
}

variable "subdomain" {
  description = "The subdomain for the documentation site"
  default = "docs"
}

variable "bucket_name" {
  description = "The name of the S3 bucket for the Docusaurus app"
  default = "marketplacepro-docs"
}
