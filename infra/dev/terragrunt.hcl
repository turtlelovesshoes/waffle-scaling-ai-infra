terraform {
  source = "../shared"
}

remote_state {
  backend = "s3"
  config = {
    bucket = "spaceliftstate"          # your existing bucket
    key    = "dev/terraform.tfstate"   # path in bucket
    region = "us-west-2"
    encrypt = true
    # dynamodb_table = "spacelift-terraform-locks" # optional if you have one
  }
}

inputs = {
  env = "dev"
}

locals {
  exclude_dirs = [".terragrunt-cache", ".terraform.lock.hcl"]
}
