terraform {
  required_version = ">= 1.0.0"
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.120.0"
    }
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

module "vpc" {
  source       = "../../modules/vpc"
  network_name = "stage-vpc"

  subnets = {
    "subnet-a" = {
      zone = "ru-central1-a"
      cidr = "192.168.10.0/24"
    }
    "subnet-b" = {
      zone = "ru-central1-b"
      cidr = "192.168.11.0/24"
    }
    "subnet-d" = {
      zone = "ru-central1-d"
      cidr = "192.168.12.0/24"
    }
  }
}

module "k8s_cluster" {
  source          = "../../modules/k8s_cluster"
  subnet_ids      = module.vpc.subnet_ids
  public_key_path = var.public_key_path
}

