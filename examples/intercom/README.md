## Terraform/OpenTofu Example - Intercom Solution

This solution will automaticall create a complete Open Intercom solution with the following components:

- Sympony Media Bridge
- Open Intercom Manager
- CouchDB for the intercom database

See general guidelines [here](../../README.md#quick-guide---general)

### Solution variables

- Env variables that needs to be set

```bash
export TF_VAR_osc_pat = <osc personal access token>
export TF_VAR_smb_api_key = <the api key used by the smb server>
export TF_VAR_db_admin_password = <the admin password for the database created>
```

- Optional variables

  - `use_latest` (bool, default `false`): provision the Symphony Media Bridge, CouchDB and
    Intercom Manager instances from their latest built images instead of the pinned stable
    catalog release. Meant for testing pre-release builds, not for production.

### Provider

This example uses `terraform-provider-osc` `~> 1.0`, which manages every service instance
through the single generic `osc_instance` resource (`service_id` + `parameters`/`sensitive_parameters`)
instead of the per-service typed resources used in `0.x` releases.
