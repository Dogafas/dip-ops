terraform {
  required_version = ">= 1.0.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.120.0"
    }
  }

  backend "s3" {
    endpoints = {
      s3 = "https://storage.yandexcloud.net"
    }
    bucket = "chipguru-diploma-tf-state"
    region = "ru-central1"
    key    = "global/s3/terraform.tfstate"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

provider "yandex" {
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.default_zone
  service_account_key_file = var.service_account_key_file
  storage_access_key       = var.storage_access_key
  storage_secret_key       = var.storage_secret_key
}

# ============================================
# Ресурс S3-бакета для бэкенда
# ============================================

resource "yandex_storage_bucket" "terraform_state" {
  bucket     = var.bucket_name
  access_key = var.storage_access_key
  secret_key = var.storage_secret_key

  lifecycle {
    prevent_destroy = true
  }

  versioning {
    enabled = true
  }
}
