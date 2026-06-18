## Terraform/OpenTofu Example - C2PA Demo Platform

Deploy a C2PA (Coalition for Content Provenance and Authenticity) demo platform for live video streaming. The platform demonstrates two approaches for per-segment content authenticity verification in DASH and HLS streams.

### What you get

- **Landing page** with interactive comparison of both C2PA approaches
- **emsg player** (Unified Streaming approach) — DASH with `emsg` boxes carrying COSE_Sign1 signatures
- **uuid player** (EZDRM/Qualabs approach) — DASH + HLS with `uuid` boxes and CBC hash chaining
- **Hack toggle** — Live MITM attack simulation showing verification detecting tampered segments
- **Upload & Sign** — Import CMAF content and sign it with either approach

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    C2PA Demo Platform                        │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   Landing    │───▶│    Signer    │    │    MinIO     │  │
│  │  (Web Runner)│    │ (Web Runner) │───▶│  (Storage)   │  │
│  │              │───▶│              │    │              │  │
│  │  dash.js     │    │  emsg sign   │    │  segments    │  │
│  │  hls.js      │    │  uuid sign   │    │  manifests   │  │
│  │  C2PA verify │    │  COSE_Sign1  │    │  keys        │  │
│  └──────┬───────┘    └──────────────┘    └──────────────┘  │
│         │                                                   │
│  ┌──────┴───────┐    ┌──────────────┐                      │
│  │  App Config  │    │    Valkey    │                      │
│  │  (Params)    │───▶│   (State)   │                      │
│  └──────────────┘    └──────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

### Services used

| Service | Purpose |
|---------|---------|
| MinIO | S3-compatible storage for video segments and manifests |
| Valkey | State management for signing jobs and hack toggle |
| App Config Service | Parameter store for shared configuration |
| Web Runner (signer) | Background signing worker with emsg and uuid support |
| Web Runner (landing) | Landing page, players, stream proxy, API |

### Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `osc_pat` | Yes | - | Eyevinn OSC Personal Access Token |
| `osc_environment` | No | `prod` | OSC Environment (prod/stage/dev) |
| `name` | No | `c2pademo` | Solution name (lowercase letters and numbers only) |
| `minio_username` | Yes | - | MinIO root username |
| `minio_password` | Yes | - | MinIO root password |
| `minio_bucket` | No | `c2pa` | S3 bucket name |
| `valkey_password` | No | auto-generated | Password for Valkey instance |

### Prerequisites

- AWS CLI installed (for bucket creation)
- Terraform >= 1.6.0 or OpenTofu >= 1.6.0

### Quick Start

1. Set your OSC Personal Access Token and MinIO credentials:
   ```bash
   export TF_VAR_osc_pat=<your-token>
   export TF_VAR_minio_username=<username>
   export TF_VAR_minio_password=<password>
   ```

2. Initialize and apply:
   ```bash
   terraform init
   terraform apply
   ```

3. Access the demo platform at the `demo_url` output.

### Outputs

| Output | Description |
|--------|-------------|
| `demo_url` | Main landing page URL |
| `emsg_player_url` | Direct link to emsg demo player |
| `uuid_player_url` | Direct link to uuid demo player |
| `signer_url` | Signing service URL |
| `minio_instance_url` | MinIO storage URL |

### C2PA Approaches

**emsg (Unified Streaming)**
- Event Message boxes with scheme URI `urn:c2pa:verifiable-segment-info`
- Full-box hashing (sidx + moof + mdat)
- DASH only
- Per-segment COSE_Sign1 (ECDSA P-256)

**uuid (EZDRM/Qualabs)**
- UUID boxes with C2PA JUMBF identifier
- mdat-only hashing with CBC hash chaining
- Anchor resets every 10 segments
- DASH + HLS (CMAF fMP4)
- Per-segment COSE_Sign1 (ECDSA P-256)

### Source repositories

- [Eyevinn/c2pa-demo-landing](https://github.com/Eyevinn/c2pa-demo-landing) — Landing page, players, API
- [Eyevinn/c2pa-demo-signer](https://github.com/Eyevinn/c2pa-demo-signer) — Signing worker

See general guidelines [here](../../README.md#quick-guide---general)
