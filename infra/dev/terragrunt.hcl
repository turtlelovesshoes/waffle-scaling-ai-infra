terraform {
  source = "../shared"
}

inputs = {
  env = "dev"
}

locals {
  exclude_dirs = [".terragrunt-cache", ".terraform.lock.hcl"]
}

# Hook to refresh state before plan
terraform {
  extra_arguments "refresh" {
    commands = ["plan", "apply"]
    arguments = ["-refresh=true"]
  }
}
