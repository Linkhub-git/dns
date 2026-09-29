# Registros de app.linkhub.ai a partir de zonas/app.linkhub.ai.yaml.
# La zona (app-linkhub-ai) ya existe y no la gestiona Terraform: solo sus registros.

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  backend "gcs" {
    bucket = "linkhub-dns-tfstate"
    prefix = "app.linkhub.ai"
  }
}

provider "google" {
  project = "linkhub-dns"
}

locals {
  zona      = "app-linkhub-ai"
  dominio   = "app.linkhub.ai."
  registros = yamldecode(file("${path.module}/zonas/app.linkhub.ai.yaml")).registros
}

resource "google_dns_record_set" "registro" {
  for_each = { for r in local.registros : "${lower(r.nombre)}/${upper(r.tipo)}" => r }

  managed_zone = local.zona
  name         = "${lower(each.value.nombre)}.${local.dominio}"
  type         = upper(each.value.tipo)
  ttl          = try(each.value.ttl, 300)
  rrdatas      = [for v in each.value.valores : upper(each.value.tipo) == "TXT" ? "\"${v}\"" : tostring(v)]
}
