terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"

      # configuration_aliases declares that this module accepts a second
      # AWS provider configured for us-east-1. CloudFront requires certificates
      # in us-east-1 regardless of where your workload runs.
      # The caller must pass: providers = { aws.us_east_1 = aws.us_east_1 }
      configuration_aliases = [aws.us_east_1]
    }
  }
}
