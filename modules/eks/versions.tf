terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # tls provider fetches the OIDC issuer certificate thumbprint
    # required when creating the aws_iam_openid_connect_provider for IRSA
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
