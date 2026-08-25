provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "aws-security-specialty-lab"
      Lab         = "lab02"
      Environment = "study"
      ManagedBy   = "terraform"
    }
  }
}
