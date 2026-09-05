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
  default     = "ru-central1-a"
  description = "Default availability zone in Yandex Cloud"
}

variable "service_account_key_file" {
  type        = string
  description = "Path to service account authorized key JSON file"
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

variable "bucket_name" {
  type        = string
  description = "Globally unique name for the Terraform state S3 bucket"
  default     = "chipguru-diploma-tf-state"
}