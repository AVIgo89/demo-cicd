terraform {
  required_version = ">= 1.6"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.115"
    }
  }

  backend "s3" {
    endpoint                    = "https://storage.yandexcloud.net"
    bucket                      = "demo-cicd-tfstate-avigo89"
    region                      = "ru-central1"
    key                         = "terraform.tfstate"
    access_key                  = ""
    secret_key                  = ""

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
