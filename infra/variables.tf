variable "aws_region" {
  description = "AWS Region for all resources."
  type        = string
  default     = "eu-north-1"
}

variable "allowed_cidrs" {
  description = "IPv4 CIDR ranges allowed to reach the load balancer on port 80. Narrow it to your own /32 for a demo."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}