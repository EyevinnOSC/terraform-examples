## Terraform/OpenTofu Example - TAMS pipeline

This solution deploys a complete [TAMS](https://github.com/bbc/tams) (Time-addressable Media Store) gateway on OSC, using the following components

- TAMS Gateway (the TAMS API)
- MinIO (S3 compatible storage for media essence)
- CouchDB (segment/flow metadata index)

The bucket name is a deploy input, so MinIO and CouchDB are provisioned in parallel. The only hard ordering edge is that the bucket must exist before the gateway boots, since the gateway never creates buckets itself. `create_buckets.sh` retries to absorb MinIO startup.

See general guidelines [here](../../README.md#quick-guide---general)

### Solution variables

- Env variables that need to be set

```bash
export TF_VAR_osc_pat = <osc personal access token>
export TF_VAR_minio_username = <User name for the MinIO storage, min 3 chars>
export TF_VAR_minio_password = <Password for the MinIO storage, min 10 chars, upper+lower+digit>
export TF_VAR_couchdb_password = <Password for the CouchDB admin user>
```

Optional variables (with defaults): `tams_name` (default `tams`), `tams_bucket` (default `tams`), `osc_environment` (default `prod`). Use a dot-free bucket name.

### Provider

This example requires the `EyevinnOSC/osc` provider `>= 0.8.0`, which is the first release to expose the required `s3_bucket` argument on `osc_eyevinn_tams_gateway`.

### AWS CLI

! Note that the AWS CLI has to be installed since the terraform deployment takes care of creating the bucket automatically

For installing, please see: [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html)

Note!! - S3 CLI Env Var `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` must match `minio_username` and `minio_password`

### Using

1. Deploy the solution using the terraform/tofu script

   ```bash
   terraform init
   terraform apply
   ```

   The deployment outputs the gateway, MinIO and CouchDB instance URLs.

2. The gateway runs behind the OSC ingress access gate, which authenticates callers by validating a Service Access Token (SAT) before the request reaches the gateway. Obtain a SAT and call the API with it:

   ```bash
   npx @osaas/cli service-access-token eyevinn-tams-gateway
   curl -H "Authorization: Bearer <sat>" <tams_gateway_url>/
   ```

### CouchDB backups (not in this template)

`eyevinn-db-backuper` performs a single backup or restore and exits (it is a job, not a long-running service), so it is intentionally not a deploy-time resource here. Schedule recurring CouchDB backups after deploy via OSC's backup scheduler against the CouchDB instance, targeting a backups bucket.

### Native AWS S3 instead of MinIO

This template wires MinIO and sets `s3_endpoint_url` to the MinIO instance (path-style). The gateway also supports native AWS S3: leave `S3_ENDPOINT_URL` unset and the SDK resolves the endpoint from `AWS_REGION`. To target AWS instead of MinIO you would drop the MinIO resource, create the bucket out-of-band, and supply real IAM credentials as `aws_access_key_id` / `aws_secret_access_key`. Use a dot-free bucket name for AWS (virtual-hosted TLS).
