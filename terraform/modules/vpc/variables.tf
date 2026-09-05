variable "network_name" {
  type        = string
  description = "VPC network name"
  default     = "diploma-vpc"
}

variable "subnets" {
  type = map(object({
    zone = string
    cidr = string
  }))
  description = "Map of subnets with zone and CIDR block"
}