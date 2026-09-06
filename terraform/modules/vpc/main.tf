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

# NAT-шлюз для обеспечения выхода в интернет из приватных подсетей
resource "yandex_vpc_gateway" "nat_gateway" {
  name = "${var.network_name}-nat-gw"
  shared_egress_gateway {}
}

# Таблица маршрутизации по умолчанию через NAT-шлюз
resource "yandex_vpc_route_table" "nat_route_table" {
  name       = "${var.network_name}-nat-rt"
  network_id = yandex_vpc_network.this.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}

resource "yandex_vpc_subnet" "this" {
  for_each       = var.subnets
  name           = "${var.network_name}-${each.key}"
  zone           = each.value.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [each.value.cidr]
  route_table_id = yandex_vpc_route_table.nat_route_table.id
}
