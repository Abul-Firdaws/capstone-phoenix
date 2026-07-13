# Remote state — required by the brief so *.tfstate never lives in git.
# 1. Create the bucket + lock table FIRST (see RUNBOOK.md for the exact aws cli commands).
# 2. Replace the bucket name below with your own globally-unique name.
# 3. This block cannot use variables — values must be hardcoded here.
terraform {
  backend "s3" {
    bucket         = "phoenix-tfstate-firdaws-22731"
    key            = "phoenix/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "phoenix-tf-lock"
    encrypt        = true
  }
}
