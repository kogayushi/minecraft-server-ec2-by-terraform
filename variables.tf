variable "basic_auth_username" {
  description = "The username for basic authentication"
  type        = string
}

variable "basic_auth_password" {
  description = "The password for basic authentication"
  type        = string
  sensitive   = true
}