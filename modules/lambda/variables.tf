variable "name_prefix" {
  description = "Name prefix for resources"
  type = string
}

variable "environment" {
  description = "Environment name"
  type = string
}

variable "source_path" {
  description = "Path to the source code"
  type = string
}

variable "handler" {
  description = "Lambda handler"
  type = string
}

variable "runtime" {
  description = "Lambda runtime"
  type    = string
  default = "python3.12"
}
