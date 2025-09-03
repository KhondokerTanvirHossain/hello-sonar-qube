variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "sonarqube"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}

variable "db_password" {
  description = "Database password (auto-generated if not provided)"
  type        = string
  default     = ""
  sensitive   = true
}