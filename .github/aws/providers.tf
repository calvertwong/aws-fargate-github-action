provider "aws" {
  region = "${var.REGION}"
  access_key = "${var.AWS_IAM_ACCESS_KEY}"
  secret_key = "${var.AWS_IAM_SECRET_KEY}"
}
