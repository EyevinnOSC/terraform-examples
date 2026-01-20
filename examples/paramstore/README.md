## Terraform/OpenTofu Example - Parameter Store

Deploy a parameter store solution using Eyevinn App Config Service backed by Valkey for persistent key-value storage. This provides a centralized configuration management service for your applications.

### Architecture

```
┌─────────────────────┐      ┌─────────────────────┐
│  App Config Service │─────▶│       Valkey        │
│    (REST API)       │      │  (Key-Value Store)  │
└─────────────────────┘      └─────────────────────┘
```

### Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `osc_pat` | Yes | - | Eyevinn OSC Personal Access Token |
| `osc_environment` | No | `prod` | OSC Environment (prod/stage/dev) |
| `paramstore_name` | No | `myparamstore` | Name of the solution (lowercase letters and numbers only) |
| `valkey_password` | No | auto-generated | Password for Valkey instance |

### Quick Start

1. Set your OSC Personal Access Token:
   ```bash
   export TF_VAR_osc_pat=<your-token>
   ```

2. Initialize and apply:
   ```bash
   terraform init
   terraform apply
   ```

3. Access the App Config Service at the `app_config_svc_instance_url` output.

See general guidelines [here](../../README.md#quick-guide---general)
