## Terraform/OpenTofu Example - Intercom Solution

This solution will automaticall create a complete Open Intercom solution with the following components:

- Sympony Media Bridge
- Open Intercom Manager
- CouchDB for the intercom database

See general guidelines [here](../../README.md#quick-guide---general)

### Solution variables

- see \*.tfvars
- Env variables

```bash
export TF_VAR_osc_pat = <osc personal access token>
export TF_VAR_smb_api_key = <the api key used by the smb server>
export TF_VAR_db_admin_password = <the admin password for the database created>
```
