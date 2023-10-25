terraform {
  required_providers {
    vault = {
      source = "hashicorp/vault"
      version = "~> 3.18.0"
    }

    nomad = {
      source = "hashicorp/nomad"
      version = "2.0.0-beta.1"
    }

    consul = {
      source = "hashicorp/consul"
      version = "2.18.0"
    }
  }
}

provider "consul" {
  address = "${data.terraform_remote_state.hcp_clusters.outputs.consul_public_endpoint}:443"
  token = data.terraform_remote_state.hcp_clusters.outputs.consul_root_token
  scheme  = "https" 
}

data "terraform_remote_state" "networking" {
  backend = "remote"

  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "1_networking"
    }
  }
}

data "terraform_remote_state" "hcp_clusters" {
  backend = "remote"

  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "2_hcp-clusters"
    }
  }
}

data "terraform_remote_state" "nomad_cluster" {
  backend = "remote"

  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "5_nomad-cluster"
    }
  }
}

data "terraform_remote_state" "nomad_nodes" {
  backend = "remote"

  config = {
    organization = var.tfc_organization
    workspaces = {
      name = "6_nomad-nodes"
    }
  }
}

provider "vault" {}

data "vault_kv_secret_v2" "bootstrap" {
  mount = data.terraform_remote_state.nomad_cluster.outputs.bootstrap_kv
  name  = "nomad_bootstrap/SecretID"
}

provider "nomad" {
  address = data.terraform_remote_state.nomad_cluster.outputs.nomad_public_endpoint
  secret_id = data.vault_kv_secret_v2.bootstrap.data["SecretID"]
}

resource "nomad_job" "mongodb" {
  hcl2 {
    vars = {
      image = var.mongodb_image
      stack_id = var.stack_id
    }
  }
  jobspec = <<EOT
variable "image" {
  type = string
}
variable "stack_id" {
  type = string
}
job "${var.stack_id}-mongodb" {
    datacenters = ["dc1"]
    node_pool = "arm"
    type = "service"

    group "${var.stack_id}-mongodb" {
        network {
            mode = "bridge"
            port "http" {
                static = 27017
                to     = 27017
            }
        }

        service {
            name = "${var.stack_id}-mongodb"
            port = "27017"
            address = "$${attr.unique.platform.aws.public-ipv4}"

            connect{
                sidecar_service {}
            }
        } 

        task "${var.stack_id}-mongodb" {
            driver = "docker"

            config {
                image = var.image
            }
            env {
                # This will immedietely be rotated be Vault
                MONGO_INITDB_ROOT_USERNAME = "admin"
                MONGO_INITDB_ROOT_PASSWORD = "password"
            }
        }
    }
}
EOT
}

resource "null_resource" "wait_for_db" {
  depends_on = [nomad_job.mongodb]

  provisioner "local-exec" {
    command = "sleep 10 && bash wait-for-nomad-job.sh ${nomad_job.mongodb.id} ${data.terraform_remote_state.nomad_cluster.outputs.nomad_public_endpoint} ${data.vault_kv_secret_v2.bootstrap.data["SecretID"]}"
  }
}

data "consul_service" "mongo_service" {
    depends_on = [ null_resource.wait_for_db ]
    name = "${var.stack_id}-mongodb"
}

resource "vault_database_secrets_mount" "mongodb" {
  depends_on = [
    null_resource.wait_for_db
  ]
  lifecycle {
    ignore_changes = [
      mongodb[0].password
    ]
  }
  path = "${var.stack_id}-mongodb"

  mongodb {
    name                 = "${var.stack_id}-mongodb"
    username             = "admin"
    password             = "password"
    connection_url       = "mongodb://{{username}}:{{password}}@${[for s in data.consul_service.mongo_service.service : s.address][0]}:27017/admin?tls=false"
    max_open_connections = 0
    allowed_roles = [
      "demo",
    ]
  }
}

resource "null_resource" "mongodb_root_rotation" {
  depends_on = [
    vault_database_secrets_mount.mongodb
  ]
  provisioner "local-exec" {
    command = "curl --header \"X-Vault-Token: ${data.terraform_remote_state.hcp_clusters.outputs.vault_root_token}\" --request POST ${data.terraform_remote_state.hcp_clusters.outputs.vault_public_endpoint}/v1/${vault_database_secrets_mount.mongodb.path}/rotate-root/${var.stack_id}-mongodb"
  }
}

resource "vault_database_secret_backend_role" "mongodb" {
  name    = "demo"
  backend = vault_database_secrets_mount.mongodb.path
  db_name = vault_database_secrets_mount.mongodb.mongodb[0].name
  creation_statements = [
    "{\"db\": \"admin\",\"roles\": [{\"role\": \"root\"}]}"
  ]
}

resource "nomad_job" "frontend" {
  depends_on = [
    vault_database_secret_backend_role.mongodb
  ]
  hcl2 {
    vars = {
      image = var.frontend_app_image
      stack_id = var.stack_id
    }
  }
  jobspec = <<EOT
variable "image" {
  type = string
}
variable "stack_id" {
  type = string
}
job "${var.stack_id}-frontend" {
    datacenters = ["dc1"]
    node_pool = "x86"
    type = "service"
    
    group "${var.stack_id}-frontend" {
        network {
            mode = "bridge"

            port "http" {
                static = 3100
                to     = 3100
            }
        }
        service {
            name = "${var.stack_id}-frontend"
            port = "http"
            address = "$${attr.unique.platform.aws.public-ipv4}"

            connect {
                sidecar_service {
                    proxy {
                        upstreams {
                            destination_name = "${var.stack_id}-mongodb"
                            local_bind_port  = 27017
                        }
                    }
                }
            }
        }
        task "${var.stack_id}-frontend" {
            driver = "docker"
            vault {
                policies = ["nomad"]
                change_mode   = "restart"
            }
            template {
                data = <<EOH
MONGOKU_DEFAULT_HOST={{ with secret "${var.stack_id}-mongodb/creds/demo" }}{{ .Data.username }}:{{ .Data.password }}{{ end }}@127.0.0.1:27017
EOH
                destination = "secrets/mongoku.env"
                env         = true
            }

            config {
                image = var.image
            }
        }
    }
} 
EOT
}

data "consul_service" "frontend_service" {
    depends_on = [ nomad_job.frontend ]
    name = "${var.stack_id}-frontend"
}

resource "consul_intention" "example" {
  count = var.create_consul_intention ? 1 : 0

  source_name      = data.consul_service.frontend_service.name
  destination_name = data.consul_service.mongo_service.name
  action           = "allow"
} 