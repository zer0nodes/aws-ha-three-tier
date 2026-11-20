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

variable "instance_type" {
  description = "EC2 instance type for the app tier. Must be x86_64 to match the AMI."
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum number of app instances."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of app instances."
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Initial number of app instances. Later changes come from scaling, so Terraform ignores them."
  type        = number
  default     = 2
}

variable "app_version" {
  description = "Version label shown by the app. Changing it rolls out new instances through an instance refresh."
  type        = string
  default     = "v1"
}
