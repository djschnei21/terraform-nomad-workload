variable "stack_id" {
  type        = string
  default = "hashistack"
  description = "The name of your stack"
}

variable "tfc_organization" {
  type    = string
  default = "djs-tfcb"
  description = "The TFCB organization to use"
}

variable "region" {
  type        = string
  default = "us-east-2"
  description = "The AWS and HCP region to create resources in"
}

variable "app_image" {
  type = string
  description = "for demo: huggingface/mongoku:latest"
}