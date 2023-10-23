
# WARNING: Generated module tests should be considered experimental and be reviewed by the module author.

variables {
  stack_id = "test-stack"
  tfc_organization = "test-org"
  region = "us-west-2"
}

run "variable_validation" {
  assert {
    condition     = var.stack_id == "test-stack"
    error_message = "incorrect value for stack_id"
  }

  assert {
    condition     = var.tfc_organization == "test-org"
    error_message = "incorrect value for tfc_organization"
  }

  assert {
    condition     = var.region == "us-west-2"
    error_message = "incorrect value for region"
  }
}