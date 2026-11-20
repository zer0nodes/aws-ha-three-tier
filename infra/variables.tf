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

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "Run RDS as Multi-AZ with a standby in the second zone. Doubles the database cost."
  type        = bool
  default     = false
}