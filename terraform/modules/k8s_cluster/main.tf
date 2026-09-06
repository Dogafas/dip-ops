terraform {
  required_version = ">= 1.0.0"
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.120.0"
    }
  }
}

data "yandex_compute_image" "ubuntu" {
  family = var.os_image_family
}

# -------------------------------------------------------------
# Master-узел (Control plane + SSH Bastion)
# -------------------------------------------------------------
resource "yandex_compute_instance" "master" {
  name        = "k8s-master-01"
  hostname    = "k8s-master-01"
  zone        = "ru-central1-a"
  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = var.subnet_ids["subnet-a"]
    nat       = true # Единственный публичный IP в кластере
  }

  metadata = {
    ssh-keys           = "ubuntu:${file(pathexpand(var.public_key_path))}"
    serial-port-enable = 1
  }

  scheduling_policy {
    preemptible = false
  }
}

# -------------------------------------------------------------
# Worker-узлы (Приватный контур, прерываемые ВМ)
# -------------------------------------------------------------
locals {
  workers = {
    "worker-01" = {
      zone      = "ru-central1-b"
      subnet_id = var.subnet_ids["subnet-b"]
    }
    "worker-02" = {
      zone      = "ru-central1-d"
      subnet_id = var.subnet_ids["subnet-d"]
    }
  }
}

resource "yandex_compute_instance" "workers" {
  for_each    = local.workers
  name        = "k8s-${each.key}"
  hostname    = "k8s-${each.key}"
  zone        = each.value.zone
  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id = each.value.subnet_id
    nat       = false # Только приватный IP, выход в сеть через NAT Gateway
  }

  metadata = {
    ssh-keys           = "ubuntu:${file(pathexpand(var.public_key_path))}"
    serial-port-enable = 1
  }

  scheduling_policy {
    preemptible = true
  }
}
