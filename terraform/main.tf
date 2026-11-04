provider "yandex" {
  service_account_key_file = "${path.module}/key.json"
  cloud_id                 = var.yc_cloud_id
  folder_id                = var.yc_folder_id
  zone                     = var.yc_zone
}

# ---------- Сеть ----------

resource "yandex_vpc_network" "k3s" {
  name = "k3s-network"
}

resource "yandex_vpc_subnet" "k3s" {
  name           = "k3s-subnet"
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.k3s.id
  v4_cidr_blocks = ["10.0.1.0/24"]
}

resource "yandex_vpc_security_group" "k3s" {
  name       = "k3s-sg"
  network_id = yandex_vpc_network.k3s.id

  ingress {
    description    = "SSH"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description    = "HTTP"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description    = "HTTPS"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description    = "k3s API"
    protocol       = "TCP"
    port           = 6443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description    = "Allow all outgoing"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- Статический IP ----------

resource "yandex_vpc_address" "k3s" {
  name = "k3s-ip"
  external_ipv4_address {
    zone_id = var.yc_zone
  }
}

# ---------- VM ----------

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

resource "yandex_compute_instance" "k3s" {
  name        = "k3s-node"
  platform_id = "standard-v3"
  zone        = var.yc_zone

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.image_id
      size     = 30
      type     = "network-hdd"   # или network-hdd, если квота позволяет
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.k3s.id
    nat                = true
    nat_ip_address     = yandex_vpc_address.k3s.external_ipv4_address[0].address
    security_group_ids = [yandex_vpc_security_group.k3s.id]
  }

  metadata = {
    ssh-keys  = "ubuntu:${var.ssh_public_key}"
    user-data = templatefile("${path.module}/cloud-init.yaml", {
      public_ip = yandex_vpc_address.k3s.external_ipv4_address[0].address
    })
  }
}

output "public_ip" {
  value = yandex_vpc_address.k3s.external_ipv4_address[0].address
}
