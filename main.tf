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
  jobspec = file("${path.module}/nomad-jobs/mongodb.hcl")
}

resource "null_resource" "wait_for_db" {
  depends_on = [nomad_job.mongodb]

  provisioner "local-exec" {
    command = "sleep 10 && bash wait-for-nomad-job.sh ${nomad_job.mongodb.id} ${data.terraform_remote_state.nomad_cluster.outputs.nomad_public_endpoint} ${data.vault_kv_secret_v2.bootstrap.data["SecretID"]}"
  }
}

data "consul_service" "mongo_service" {
    depends_on = [ null_resource.wait_for_db ]
    name = "demo-mongodb"
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
  path = "mongodb"

  mongodb {
    name                 = "mongodb-on-nomad"
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
    command = "curl --header \"X-Vault-Token: ${data.terraform_remote_state.hcp_clusters.outputs.vault_root_token}\" --request POST ${data.terraform_remote_state.hcp_clusters.outputs.vault_public_endpoint}/v1/${vault_database_secrets_mount.mongodb.path}/rotate-root/mongodb-on-nomad"
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
      app_image = var.app_image
    }
  }
  jobspec = <<EOT
variable "app_image" {
  type = string
}
job "demo-frontend" {
    datacenters = ["dc1"]
    node_pool = "x86"
    type = "service"
    
    group "frontend" {
        network {
            mode = "bridge"

            port "http" {
                static = 3100
                to     = 3100
            }
        }
        service {
            name = "demo-frontend"
            port = "http"
            address = "$${attr.unique.platform.aws.public-ipv4}"

            connect {
                sidecar_service {
                    proxy {
                        upstreams {
                            destination_name = "demo-mongodb"
                            local_bind_port  = 27017
                        }
                    }
                }
            }
        }
        task "frontend" {
            driver = "docker"
            vault {
                policies = ["nomad"]
                change_mode   = "restart"
            }
            template {
                data = <<EOH
MONGOKU_DEFAULT_HOST={{ with secret "mongodb/creds/demo" }}{{ .Data.username }}:{{ .Data.password }}{{ end }}@127.0.0.1:27017
EOH
                destination = "secrets/mongoku.env"
                env         = true
            }

            config {
                image = var.app_image
            }
        }
    }
} 
EOT
}