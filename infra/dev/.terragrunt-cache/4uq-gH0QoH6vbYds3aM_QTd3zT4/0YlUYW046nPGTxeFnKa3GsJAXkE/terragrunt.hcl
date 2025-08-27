terraform {
  source = "../shared"
}

remote_state {
  backend = "s3"
  config = {
    bucket = "spaceliftstate"
    key    = "dev/terraform.tfstate"   # path in the bucket
    region = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

inputs = {
  env = "dev"
}
