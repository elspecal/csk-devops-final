# Remote state in S3 with lockfile locking
terraform {
  backend "s3" {
    key          = "csepella-eks-reverse-proxy/terraform.tfstate"
    bucket       = "csepella-w10-362099375729-eu-west-3-an"
    region       = "eu-west-3"
    use_lockfile = true
    encrypt      = true
  }
}
