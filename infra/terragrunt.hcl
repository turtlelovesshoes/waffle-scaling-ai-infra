locals { project = "waffle-scaling-ai-infra" }

generate "provider" {
  path      = "provider_generated.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform { required_version = ">= 1.5.0" }
EOF
}
