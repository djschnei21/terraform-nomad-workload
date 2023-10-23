
# WARNING: Generated module tests should be considered experimental and be reviewed by the module author.

variables {
  stack_id = "test-stack"
  tfc_organization = "test-org"
  region = "us-west-2"
}

run "provider_validation" {
  assert {
    condition     = provider.doormat != null
    error_message = "doormat provider not initialized"
  }

  assert {
    condition     = provider.aws != null
    error_message = "aws provider not initialized"
  }

  assert {
    condition     = provider.vault != null
    error_message = "vault provider not initialized"
  }

  assert {
    condition     = provider.nomad != null
    error_message = "nomad provider not initialized"
  }

  assert {
    condition     = provider.consul != null
    error_message = "consul provider not initialized"
  }
}

run "resource_validation" {
  assert {
    condition     = nomad_job.mongodb != null
    error_message = "nomad_job.mongodb not initialized"
  }

  assert {
    condition     = null_resource.wait_for_db != null
    error_message = "null_resource.wait_for_db not initialized"
  }

  assert {
    condition     = consul_service.mongo_service != null
    error_message = "consul_service.mongo_service not initialized"
  }

  assert {
    condition     = vault_database_secrets_mount.mongodb != null
    error_message = "vault_database_secrets_mount.mongodb not initialized"
  }

  assert {
    condition     = null_resource.mongodb_root_rotation != null
    error_message = "null_resource.mongodb_root_rotation not initialized"
  }

  assert {
    condition     = vault_database_secret_backend_role.mongodb != null
    error_message = "vault_database_secret_backend_role.mongodb not initialized"
  }

  assert {
    condition     = nomad_job.frontend != null
    error_message = "nomad_job.frontend not initialized"
  }
}

run "data_validation" {
  assert {
    condition     = data.doormat_aws_credentials.creds != null
    error_message = "data.doormat_aws_credentials.creds not initialized"
  }

  assert {
    condition     = data.terraform_remote_state.networking != null
    error_message = "data.terraform_remote_state.networking not initialized"
  }

  assert {
    condition     = data.terraform_remote_state.hcp_clusters != null
    error_message = "data.terraform_remote_state.hcp_clusters not initialized"
  }

  assert {
    condition     = data.terraform_remote_state.nomad_cluster != null
    error_message = "data.terraform_remote_state.nomad_cluster not initialized"
  }

  assert {
    condition     = data.terraform_remote_state.nomad_nodes != null
    error_message = "data.terraform_remote_state.nomad_nodes not initialized"
  }

  assert {
    condition     = data.vault_kv_secret_v2.bootstrap != null
    error_message = "data.vault_kv_secret_v2.bootstrap not initialized"
  }

  assert {
    condition     = data.consul_service.mongo_service != null
    error_message = "data.consul_service.mongo_service not initialized"
  }
}