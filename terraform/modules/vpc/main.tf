terraform {
  required_version = ">= 1.0.0"
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.120.0"
    }
  }
}

resource "yandex_vpc_network" "this" {
  name = var.network_name
}

resource "yandex_vpc_subnet" "this" {
  for_each       = var.subnets
  name           = "${var.network_name}-${each.key}"
  zone           = each.value.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [each.value.cidr]
}
