variable "aws_region" {
  description = "AWS region for deployment"
  default     = "eu-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "db_password" {
  description = "Password for the RDS instance"
  type        = string
  sensitive   = true
}