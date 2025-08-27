terraform {
  source = "../shared"

  extra_arguments "refresh" {
    commands  = ["plan", "apply"]
    arguments = ["-refresh=true"]
  }
}

inputs = {
  env = "dev"
}

locals {
  exclude_dirs = [".terragrunt-cache", ".terraform.lock.hcl"]
}
