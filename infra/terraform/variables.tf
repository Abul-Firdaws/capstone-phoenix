variable "aws_region" {
  description = "AWS region to build in"
  default     = "us-east-1"
}

variable "my_ip" {
  description = "Your public IP in CIDR form, e.g. 102.223.10.5/32. Find it with: curl -s ifconfig.me"
  type        = string
}

variable "key_name" {
  description = "Name of an existing AWS EC2 key pair (create it first, see RUNBOOK.md)"
  type        = string
}

variable "instance_type" {
  description = "Instance size for all 3 nodes"
  default     = "t3.medium"
}

variable "worker_count" {
  description = "Number of worker nodes. The brief requires at least 2 (3 nodes total)."
  type        = number
  default     = 2
}
