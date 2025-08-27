terraform {
  source = "../shared"
}

inputs = {
  env = "dev"
}

locals {
  exclude_dirs = [".terragrunt-cache", ".terraform.lock.hcl"]
}
