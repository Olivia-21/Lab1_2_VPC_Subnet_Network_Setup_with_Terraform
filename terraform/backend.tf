terraform {
  backend "s3" {
    bucket = "iam-buckets-cdem-lab"
    key = "iam/terraform.tfstate"
    region = "us-east-1"
    use_lockfile = true 
  }
}