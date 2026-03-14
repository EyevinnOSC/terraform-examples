## Terraform/OpenTofu Example - Mobile Backend Starter

A production-ready Backend-as-a-Service (BaaS) stack for mobile applications, composed entirely from open source software on Eyevinn OSC. Deploy a full backend in minutes with no vendor lock-in.

### What gets deployed

| Service | Role |
|---|---|
| PostgreSQL | Relational database |
| PostgREST | Auto-generated REST API from your database schema |
| MinIO | S3-compatible object storage for files and media |
| OpenAuth Password | Email/password authentication with JWT |
| Valkey | Redis-compatible cache and session store |
| Flyimg | On-demand image transforms (resize, crop, format) |
| CouchDB | User store for the auth service |

All secrets (passwords) are auto-generated unless you provide them explicitly. Service wiring is handled automatically via OSC secrets.

### Prerequisites

- An [Eyevinn OSC](https://app.osaas.io) account (paid plan recommended for SMTP access)
- Terraform >= 1.6.0 or OpenTofu >= 1.6.0
- An SMTP URL for email verification (e.g. `smtps://user:password@smtp.example.com:465`)
  - OSC paid tenants: find SMTP credentials under Team Settings > Email

### Quickstart

```bash
cd examples/mobile-backend

# Export sensitive variables
export TF_VAR_osc_pat=<YOUR OSC PERSONAL ACCESS TOKEN>
export TF_VAR_smtp_url=<YOUR SMTP URL>

# Initialize providers
terraform init

# Preview what will be created
terraform plan -var="solution_name=mybackend"

# Deploy
terraform apply -var="solution_name=mybackend"
```

After apply completes, Terraform prints all connection URLs and endpoints.

### Variables

| Name | Default | Description |
|---|---|---|
| `osc_pat` | required | OSC Personal Access Token |
| `osc_environment` | `prod` | OSC environment (`prod`, `stage`, `dev`) |
| `solution_name` | `mybackend` | Name prefix for all services. Lowercase letters and numbers only |
| `smtp_url` | required | SMTP URL for email verification |
| `database_password` | auto-generated | PostgreSQL password |
| `couchdb_password` | auto-generated | CouchDB admin password |
| `minio_password` | auto-generated | MinIO admin password |
| `valkey_password` | auto-generated | Valkey password |

### Outputs

| Name | Description |
|---|---|
| `postgresql_url` | PostgreSQL connection URL |
| `rest_api_url` | PostgREST REST API URL |
| `minio_console_url` | MinIO web console URL |
| `minio_endpoint` | MinIO S3-compatible endpoint (`host:port`) |
| `minio_access_key` | MinIO access key (S3 access key ID) |
| `auth_url` | OpenAuth Password service URL |
| `valkey_url` | Valkey connection URL (`redis://host:port`) |
| `flyimg_url` | Flyimg image transform service URL |

### Zero lock-in

Every service in this stack is open source software running on standard protocols. Your data stays in PostgreSQL and MinIO — both exportable at any time. Switch providers or self-host by pointing your connection strings elsewhere. No proprietary APIs, no vendor-specific SDKs required.

### Tear down

```bash
terraform destroy
```

See general guidelines [here](../../README.md#quick-guide---general)
