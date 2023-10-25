variable "stack_id" {
  type        = string
  description = "The name of your stack"
}

variable "tfc_organization" {
  type    = string
  description = "The TFCB organization to use"
}

variable "region" {
  type        = string
  description = "The AWS and HCP region to create resources in"
}

variable "frontend_app_image" {
  type = string
  description = "Frontend app image to deploy"
}

variable "mongodb_image" {
  type = string
  description = "MongoDB image to deploy"
}

variable "create_consul_intention" {
  type = bool
  description = "Allow the frontend to communicate with the backend (MongoDB)"
}