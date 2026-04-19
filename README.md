# EspoCRM on GCP — Terraform Deployment

Terraform-managed infrastructure deploying [EspoCRM](https://www.espocrm.com/) on Google Cloud Platform. Provisions a single GCE instance running Docker Compose (EspoCRM app, daemon, websocket, Caddy reverse proxy) backed by Cloud SQL for MySQL 8.0, with Google Workspace OIDC authentication.

Built by [JuntoAI](https://juntoai.org) — the next generation business network.

Target workload: 5 users, fewer than 1,000 contacts, 6-month horizon.

## Architecture

```text
Internet → Static IP → Caddy (TLS) → EspoCRM App (:80)
                                   → EspoCRM Websocket (:8080 via /ws)
                                   → Cloud SQL MySQL 8.0 (private IP)

DNS: crm.example.com → A record → GCE static IP (managed in AWS Route53)
Auth: Google Workspace OIDC → accounts.google.com
```

Key resources:

| Resource | Type | Details |
| --- | --- | --- |
| GCE Instance | `e2-small` | Ubuntu 22.04 LTS, 20 GB pd-standard |
| Cloud SQL | `db-f1-micro` | MySQL 8.0, private IP only, daily backups |
| VPC | Custom mode | `/24` subnet, Private Google Access |
| Static IP | Regional | PREMIUM tier, assigned to GCE |
| Secret Manager | 3 secrets | DB password, admin password, OAuth secret |
| Service Account | Least privilege | secretAccessor, logWriter, metricWriter |

See the [design document](../.kiro/specs/espocrm-gcp-deployment/design.md) for the full architecture diagram and resource dependency chain.

## Prerequisites

Before you begin, ensure you have:

1. **GCP project** — A GCP project (default: `your-gcp-project-id`) with billing enabled
2. **Terraform** — Version `~> 1.9` installed ([install guide](https://developer.hashicorp.com/terraform/install))
3. **gcloud CLI** — Authenticated with a user or service account that has `roles/owner` or equivalent on the project ([install guide](https://cloud.google.com/sdk/docs/install))
4. **GCS state bucket** — A GCS bucket for Terraform remote state. Create it manually:

   ```bash
   gcloud auth login
   gcloud config set project your-gcp-project-id

   gsutil mb -p your-gcp-project-id -l us-central1 gs://your-tf-state-bucket
   gsutil versioning set on gs://your-tf-state-bucket
   ```

5. **AWS Route53 access** — Permissions to create an A record in the `example.com` hosted zone (for DNS setup after deployment)

## Quick Start

### 1. Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
project_id             = "your-gcp-project-id"
region                 = "us-central1"
zone                   = "us-central1-a"
domain                 = "crm.example.com"
ssh_source_ranges      = ["YOUR_IP/32"]  # restrict SSH access
db_tier                = "db-f1-micro"
deletion_protection    = true
terraform_state_bucket = "your-tf-state-bucket"

# Leave OAuth fields empty for initial deployment — fill in after Step 5
oauth_client_id     = ""
oauth_client_secret = ""
```

> **Never commit `terraform.tfvars` to version control.** It contains secrets.

### 2. Initialize Terraform

```bash
terraform init -backend-config="bucket=your-tf-state-bucket"
```

This configures the GCS backend for remote state. You only need to run this once (or when changing backend config).

### 3. Review the plan

```bash
terraform plan
```

Review the output carefully. You should see approximately 20 resources being created:

- 6 API enablements
- VPC, subnet, 3 firewall rules, static IP, PSA range, PSA connection
- Cloud SQL instance, database, user
- 3 Secret Manager secrets + versions
- Service account + 3 IAM bindings
- GCE instance

### 4. Apply

```bash
terraform apply
```

Type `yes` when prompted. First deployment takes 10–15 minutes (Cloud SQL provisioning is the bottleneck).

After apply completes, note the outputs:

```bash
terraform output static_ip          # For DNS A record
terraform output instance_name      # For SSH access
terraform output instance_zone      # For SSH access
terraform output application_url    # https://crm.example.com
```

### 5. Configure DNS (Route53)

Create an A record in AWS Route53 pointing `crm.example.com` to the static IP:

1. Open the [AWS Route53 Console](https://console.aws.amazon.com/route53/)
2. Navigate to **Hosted zones** → select the `example.com` hosted zone
3. Click **Create record**
4. Configure:
   - **Record name**: `crm`
   - **Record type**: `A`
   - **Value**: paste the `static_ip` output from Terraform (e.g., `34.123.45.67`)
   - **TTL**: `300` (5 minutes — lower for initial setup, increase later)
   - **Routing policy**: Simple routing
5. Click **Create records**

Wait for DNS propagation (usually 1–5 minutes). Verify:

```bash
dig crm.example.com +short
# Should return the static IP
```

> **TLS note**: Caddy automatically provisions a Let's Encrypt certificate once DNS resolves to the static IP and ports 80/443 are reachable. The first HTTPS request may take a few seconds while the certificate is issued.

### 6. Verify deployment

Once DNS is live, open `https://crm.example.com` in your browser. You should see the EspoCRM login page.

Log in with the admin credentials:

- **Username**: `admin`
- **Password**: Retrieve from Secret Manager:

  ```bash
  gcloud secrets versions access latest --secret=espocrm-admin-password --project=your-gcp-project-id
  ```

## Manual OAuth Setup (GCP Console)

The OAuth consent screen cannot be automated via Terraform — it requires interactive configuration in the GCP Console. Complete these steps before enabling OIDC in EspoCRM.

### Step 1: Configure the OAuth consent screen

1. Go to [GCP Console → APIs & Services → OAuth consent screen](https://console.cloud.google.com/apis/credentials/consent?project=your-gcp-project-id)
2. Select **Internal** as the user type (this restricts login to your Google Workspace organization)
3. Click **Create**
4. Fill in the app information:
   - **App name**: `EspoCRM`
   - **User support email**: your admin email (e.g., `admin@example.com`)
   - **App logo**: optional
5. Under **App domain**:
   - **Application home page**: `https://crm.example.com`
   - **Application privacy policy link**: optional
   - **Application terms of service link**: optional
6. Under **Authorized domains**, add: `example.com`
7. **Developer contact information**: your admin email
8. Click **Save and Continue**
9. On the **Scopes** page, click **Add or Remove Scopes**:
   - Select `openid`, `email`, and `profile`
   - Click **Update**, then **Save and Continue**
10. Review the summary and click **Back to Dashboard**

### Step 2: Create OAuth client credentials

1. Go to [GCP Console → APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials?project=your-gcp-project-id)
2. Click **Create Credentials** → **OAuth client ID**
3. Configure:
   - **Application type**: `Web application`
   - **Name**: `EspoCRM OIDC`
   - **Authorized JavaScript origins**: `https://crm.example.com`
   - **Authorized redirect URIs**: `https://crm.example.com`
4. Click **Create**
5. A dialog shows your **Client ID** and **Client secret** — copy both

### Step 3: Update Terraform with OAuth credentials

1. Edit `terraform.tfvars`:

   ```hcl
   oauth_client_id     = "YOUR_CLIENT_ID.apps.googleusercontent.com"
   oauth_client_secret = "GOCSPX-YOUR_CLIENT_SECRET"
   ```

2. Apply the changes:

   ```bash
   terraform plan   # Review — should update the OAuth secret and GCE instance
   terraform apply
   ```

   This stores the OAuth client secret in Secret Manager and updates the GCE instance startup script with the client ID.

## Post-Deployment: OIDC Configuration in EspoCRM

After OAuth credentials are deployed, configure OIDC in the EspoCRM admin UI. Some settings are pre-configured via environment variables, but the client secret and endpoint URLs must be set manually.

1. Open `https://crm.example.com` and log in as `admin` (use the admin password from Secret Manager)
2. Navigate to **Administration** → **Authentication**
3. Verify or set the following:
   - **Authentication Method**: `OIDC` (should already be set via env var)
   - **Fallback Login**: enabled (should already be set)
4. Under **OIDC** settings, configure:
   - **Client ID**: should already be populated — verify it matches your OAuth client ID
   - **Client Secret**: paste the OAuth client secret from the GCP Console
   - **Authorization Endpoint**: `https://accounts.google.com/o/oauth2/v2/auth`
   - **Token Endpoint**: `https://oauth2.googleapis.com/token`
   - **Redirect URI**: `https://crm.example.com`
   - **Username Claim**: `email` (should already be set)
   - **Create User**: enabled (should already be set — auto-provisions new `@example.com` users)
   - **Fallback**: enabled (allows admin login with local password if OIDC is down)
5. Click **Save**
6. Test: open an incognito window, go to `https://crm.example.com`, and click the OIDC login button. Sign in with a `@example.com` Google account.

> **Troubleshooting OIDC**: The most common failure is a redirect URI mismatch. Ensure the redirect URI in EspoCRM (`https://crm.example.com`) exactly matches the authorized redirect URI in the GCP Console OAuth client.

## SSH Access and Troubleshooting

### SSH into the instance

```bash
gcloud compute ssh espocrm \
  --zone=us-central1-a \
  --project=your-gcp-project-id
```

Or use the Terraform outputs:

```bash
gcloud compute ssh $(terraform output -raw instance_name) \
  --zone=$(terraform output -raw instance_zone) \
  --project=your-gcp-project-id
```

### Check container status

```bash
cd /opt/espocrm
sudo docker compose ps
```

All 4 containers should show `Up` status:

```text
NAME                 STATUS
caddy                Up
espocrm              Up
espocrm-daemon       Up
espocrm-websocket    Up
```

### View container logs

```bash
# All containers
sudo docker compose logs -f

# Specific container
sudo docker compose logs -f espocrm
sudo docker compose logs -f caddy
sudo docker compose logs -f espocrm-daemon
sudo docker compose logs -f espocrm-websocket
```

### Check startup script logs

```bash
sudo journalctl -u google-startup-scripts --no-pager -n 100
```

### View serial console output (without SSH)

If SSH is not working, check the serial console from your local machine:

```bash
gcloud compute instances get-serial-port-output espocrm \
  --zone=us-central1-a \
  --project=your-gcp-project-id
```

### Restart the Docker Compose stack

```bash
cd /opt/espocrm
sudo docker compose down
sudo docker compose up -d
```

### Check Cloud SQL connectivity from the instance

```bash
# The DB host is the Cloud SQL private IP
sudo docker compose exec espocrm bash -c 'mysqladmin ping -h $ESPOCRM_DATABASE_HOST -u $ESPOCRM_DATABASE_USER -p$ESPOCRM_DATABASE_PASSWORD'
```

### Check TLS certificate status

```bash
# From your local machine
curl -vI https://crm.example.com 2>&1 | grep -E 'subject:|issuer:|expire'

# From the instance
sudo docker compose exec caddy caddy list-certificates
```

### Common issues

| Symptom | Likely Cause | Fix |
| --- | --- | --- |
| Site unreachable | DNS not propagated or firewall issue | Check `dig crm.example.com`, verify firewall rules in GCP Console |
| TLS certificate error | DNS not pointing to static IP yet | Wait for DNS propagation; Caddy retries automatically |
| 502 Bad Gateway | EspoCRM container not ready | Wait 1–2 minutes after boot; check `docker compose logs espocrm` |
| Database connection error | Cloud SQL not reachable | Check VPC peering status; verify private IP connectivity |
| OIDC login fails | Redirect URI mismatch | Ensure `https://crm.example.com` is in both EspoCRM and GCP Console |
| Containers not starting | Startup script failed | Check `journalctl -u google-startup-scripts` and serial console |
| SSH connection refused | Firewall `ssh_source_ranges` too restrictive | Update `ssh_source_ranges` in `terraform.tfvars` and re-apply |

## Teardown

To destroy all resources:

```bash
# First, disable deletion protection on Cloud SQL
terraform apply -var="deletion_protection=false"

# Then destroy everything
terraform destroy
```

Type `yes` when prompted. This permanently deletes:

- The GCE instance and all Docker volumes (EspoCRM data, TLS certificates)
- The Cloud SQL instance and all database data
- All Secret Manager secrets
- The VPC, firewall rules, and static IP
- The service account and IAM bindings

> **This is irreversible.** Back up any data you need before destroying. The Terraform state in GCS is not deleted by `terraform destroy` — delete the bucket manually if needed.

After destroying, remember to remove the Route53 A record for `crm.example.com` in AWS.

## Variables Reference

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `project_id` | `string` | `"your-gcp-project-id"` | GCP project ID |
| `region` | `string` | `"us-central1"` | GCP region for all regional resources |
| `zone` | `string` | `"us-central1-a"` | GCE instance zone (must be in `region`) |
| `domain` | `string` | `"crm.example.com"` | Domain for TLS cert and EspoCRM site URL |
| `ssh_source_ranges` | `list(string)` | `["0.0.0.0/0"]` | CIDR ranges allowed SSH access |
| `db_tier` | `string` | `"db-f1-micro"` | Cloud SQL machine tier |
| `db_backup_start_time` | `string` | `"03:00"` | Daily backup window start (UTC, HH:MM) |
| `deletion_protection` | `bool` | `true` | Cloud SQL deletion protection |
| `oauth_client_id` | `string` | `""` | Google OAuth 2.0 client ID |
| `oauth_client_secret` | `string` | `""` | Google OAuth 2.0 client secret (sensitive) |
| `terraform_state_bucket` | `string` | — (required) | GCS bucket for Terraform remote state |

## Outputs Reference

| Output | Description |
| --- | --- |
| `static_ip` | Static external IP — use for Route53 A record |
| `cloud_sql_connection_name` | Cloud SQL connection name (for debugging / Cloud SQL Proxy) |
| `cloud_sql_private_ip` | Cloud SQL private IP (for verification) |
| `instance_name` | GCE instance name (for `gcloud compute ssh`) |
| `instance_zone` | GCE instance zone (for `gcloud compute ssh`) |
| `application_url` | `https://crm.example.com` |

## Related Repositories

This infrastructure provisions the platform for the [JuntoAI EspoCRM ecosystem](https://github.com/JuntoAI/espocrm-workspace). No dependencies — this repo is standalone.

| Repository | Description | Dependency |
|---|---|---|
| [espocrm-chart-dashlet-extension](https://github.com/JuntoAI/espocrm-chart-dashlet-extension) | Pie and bar chart dashlets for the home dashboard | Runs on this infra |
| [espocrm-reporting-extension](https://github.com/JuntoAI/espocrm-reporting-extension) | Full-page reporting dashboard with interactive charts | Runs on this infra |
| [espocrm-ai-assistant-extension](https://github.com/JuntoAI/espocrm-ai-assistant-extension) | AI chat assistant for EspoCRM | Runs on this infra |
| [espocrm-ai-backend](https://github.com/JuntoAI/espocrm-ai-backend) | AI backend service bridging Gemini and MCP tools | Runs on this infra |
| [espocrm-mcp-server](https://github.com/JuntoAI/espocrm-mcp-server) | MCP server with 47 CRM tools | Runs on this infra |

## About JuntoAI

[JuntoAI](https://juntoai.org) is the next generation business network. We use EspoCRM as our CRM and share our infrastructure code with the community as open source.

Join the waitlist at [juntoai.org](https://juntoai.org). Found a bug? [Open an issue](https://github.com/JuntoAI/espocrm-gcp-terraform/issues) or reach out at [juntoai.org](https://juntoai.org).

## License

MIT
