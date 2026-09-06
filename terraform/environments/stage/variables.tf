variable "cloud_id" {
  type        = string
  description = "Yandex Cloud ID"
}

variable "folder_id" {
  type        = string
  description = "Yandex Cloud Folder ID"
}

variable "default_zone" {
  type        = string
  default     = "ru-central1-d"
  description = "Default availability zone"
}

variable "service_account_key_file" {
  type        = string
  description = "Path to service account key file"
}

variable "storage_access_key" {
  type        = string
  description = "Static access key for Yandex Object Storage"
  sensitive   = true
}

variable "storage_secret_key" {
  type        = string
  description = "Static secret key for Yandex Object Storage"
  sensitive   = true
}

variable "public_key_path" {
  type        = string
  description = "Path to the SSH public key"
}