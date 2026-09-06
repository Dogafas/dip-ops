variable "subnet_ids" {
  type        = map(string)
  description = "Map of subnet IDs by availability zone or alias"
}

variable "public_key_path" {
  type        = string
  description = "Path to SSH public key"
}

variable "os_image_family" {
  type        = string
  default     = "ubuntu-2204-lts"
  description = "OS Image family for VMs"
}
