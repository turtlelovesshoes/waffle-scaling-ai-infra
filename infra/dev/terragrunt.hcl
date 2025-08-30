remote_state {
  backend = "s3"
  config = {
    bucket         = "spaceliftstate"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "us-west-2"
}
EOF
}


generate "prevent_local_apply" {
  path      = "prevent_local_apply.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  required_version = ">= 1.5.0"
}

resource "null_resource" "prevent_local_apply" {
  lifecycle {
    prevent_destroy = true
  }

  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Local apply is disabled. Use Spacelift!' && exit 1"
  }
}
EOF
}

inputs = {
  env = "dev"

  # Default tags for all modules/resources
  default_tags = {
    "infracost" = "true"
    "Environment" = "dev"
  }
}
