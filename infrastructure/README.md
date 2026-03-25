# Infrastructure as Code (IaC) - Deployment Automation

This directory contains Infrastructure as Code (IaC) files for automated deployment and infrastructure management of the Nextcloud Docker Stack.

## Directory Structure

```
infrastructure/
├── ansible/                 # Ansible playbooks and roles
│   ├── deploy.yml          # Main deployment playbook
│   ├── inventory-dev.yml   # Development inventory
│   ├── inventory-prod.yml  # Production inventory
│   └── tasks/              # Reusable task files
│
├── terraform/              # Terraform modules and configurations
│   ├── aws/                # AWS deployment
│   │   ├── main.tf         # AWS infrastructure
│   │   ├── variables.tf    # Input variables
│   │   ├── outputs.tf      # Output values
│   │   └── user-data.sh    # EC2 initialization script
│   ├── azure/              # Azure deployment
│   ├── gcp/                # Google Cloud Platform
│   └── digitalocean/       # DigitalOcean deployment
│
├── kubernetes/             # Kubernetes manifests
│   ├── nextcloud.yaml      # Complete Nextcloud stack
│   ├── namespace.yaml      # K8s namespace
│   ├── configmap.yaml      # Configuration maps
│   ├── secrets.yaml        # Kubernetes secrets
│   ├── pvc.yaml            # Persistent volume claims
│   └── ingress.yaml        # Ingress configuration
│
└── pulumi/                 # Pulumi infrastructure automation
    ├── __main__.py         # Main Pulumi program
    ├── Pulumi.yaml         # Pulumi project configuration
    └── requirements.txt    # Python dependencies
```

---

## Deployment Methods

### 1. Ansible (Server Automation)

**Best for**: Multiple servers, existing infrastructure, incremental updates

```bash
cd ansible/

# Development environment
ansible-playbook -i inventory-dev.yml deploy.yml

# Production environment with vault encryption
ansible-playbook -i inventory-prod.yml deploy.yml --ask-vault-pass
```

**Features**:
- Idempotent playbooks
- Encrypted secrets management
- Multi-environment support
- Gradual rollouts
- Automated health checks

---

### 2. Terraform (Cloud Infrastructure)

**Best for**: Cloud deployments, reproducible infrastructure, state management

```bash
cd terraform/aws/

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -out=tfplan

# Apply configuration
terraform apply tfplan

# Destroy infrastructure
terraform destroy
```

**Supported Providers**:
- **AWS** - EC2, RDS, ALB, Secrets Manager
- **Azure** - VMs, AKS, Azure Database
- **GCP** - Compute Engine, Cloud SQL
- **DigitalOcean** - Droplets, Database

**Features**:
- Infrastructure as code
- State management
- Modular architecture
- Auto-scaling configuration
- Monitoring and alerts

---

### 3. Kubernetes (Container Orchestration)

**Best for**: Cloud-native deployments, auto-scaling, complex applications

```bash
cd kubernetes/

# Deploy to Kubernetes
kubectl apply -f nextcloud.yaml

# Monitor deployment
kubectl get pods -n nextcloud
kubectl logs -n nextcloud deployment/nextcloud -f

# Access Nextcloud
kubectl port-forward -n nextcloud svc/nextcloud 8080:80
```

**Features**:
- Container orchestration
- Auto-scaling (HPA)
- Rolling updates
- Health probes
- Network policies
- Resource management

**Deployment Options**:
- Manual: `kubectl apply -f`
- Helm: `helm install nextcloud/nextcloud`
- Kustomize: `kubectl apply -k`

---

### 4. Pulumi (Programmatic IaC)

**Best for**: Complex deployments, custom logic, multi-cloud

```bash
cd pulumi/

# Initialize Pulumi stack
pulumi stack init production

# Configure secrets
pulumi config set --secret nextcloud_admin_password "password"
pulumi config set domain "nextcloud.example.com"

# Preview changes
pulumi preview

# Deploy infrastructure
pulumi up

# Access outputs
pulumi stack output
```

**Supported Languages**:
- Python (.py)
- TypeScript (.ts)
- Go (.go)
- Java (.java)
- C# (.cs)

**Features**:
- Programmatic infrastructure
- Custom logic support
- Multi-cloud deployments
- Secrets management
- Policy as code

---

## Environment-Specific Configurations

### Development Environment

- **File**: `ansible/inventory-dev.yml`
- **Container Runtime**: Docker
- **Rootless Mode**: Disabled
- **Security**: Standard
- **Scaling**: Single instance
- **SSL**: Self-signed (optional)

```bash
# Deploy to development
ansible-playbook -i inventory-dev.yml deploy.yml -e "environment=dev"
```

### Production Environment

- **File**: `ansible/inventory-prod.yml`
- **Container Runtime**: Podman
- **Rootless Mode**: Enabled
- **Security**: Hardened
- **Scaling**: Multi-instance with load balancing
- **SSL**: Let's Encrypt

```bash
# Deploy to production
ansible-playbook -i inventory-prod.yml deploy.yml --ask-vault-pass
```

---

## Cloud Provider Specific Guides

### AWS Deployment

```bash
cd terraform/aws/

# Configure AWS credentials
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key

# Create terraform.tfvars
cat > terraform.tfvars << EOF
aws_region     = "us-east-1"
environment    = "production"
instance_type  = "t3.medium"
instance_count = 2
domain_name    = "nextcloud.example.com"
key_pair_name  = "your-key-pair"
EOF

# Deploy
terraform init
terraform apply
```

### Azure Deployment

```bash
cd terraform/azure/

# Login to Azure
az login

# Create terraform.tfvars
cat > terraform.tfvars << EOF
azure_region     = "eastus"
resource_group   = "nextcloud-rg"
subscription_id  = "your-subscription-id"
environment      = "production"
EOF

# Deploy
terraform apply
```

### Google Cloud Platform

```bash
cd terraform/gcp/

# Authenticate
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# Create terraform.tfvars
cat > terraform.tfvars << EOF
gcp_project_id = "your-project-id"
gcp_region     = "us-central1"
environment    = "production"
EOF

# Deploy
terraform apply
```

### DigitalOcean

```bash
cd terraform/digitalocean/

# Set Digital Ocean token
export DIGITALOCEAN_TOKEN=your_token

# Create terraform.tfvars
cat > terraform.tfvars << EOF
do_region  = "nyc3"
droplet_size = "s-2vcpu-4gb"
environment = "production"
EOF

# Deploy
terraform apply
```

---

## Ansible Vault (Encrypted Secrets)

### Create Encrypted Inventory

```bash
# Create vault password
echo "your-secret-password" > .vault_pass

# Create encrypted inventory
ansible-vault create --vault-password-file=.vault_pass inventory-prod.yml
```

### Use Vault in Playbook

```bash
# Run with vault password prompt
ansible-playbook -i inventory-prod.yml deploy.yml --ask-vault-pass

# Or use vault password file
ansible-playbook -i inventory-prod.yml deploy.yml --vault-password-file=.vault_pass
```

---

## Terraform State Management

### Local State (Development)

```bash
# State stored in terraform.tfstate (gitignored)
terraform plan
terraform apply
```

### Remote State (Production)

```bash
# Using S3 backend (AWS)
terraform {
  backend "s3" {
    bucket = "nextcloud-terraform-state"
    key    = "prod/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
  }
}

terraform init
terraform apply
```

---

## Monitoring and Logging

### Ansible Playbook Execution

```bash
# Verbose output
ansible-playbook -i inventory-prod.yml deploy.yml -vvv

# Log output to file
ansible-playbook -i inventory-prod.yml deploy.yml > deployment.log 2>&1
```

### Terraform Logging

```bash
# Enable Terraform debug logging
export TF_LOG=DEBUG
terraform apply

# Or save to file
export TF_LOG_PATH=terraform.log
terraform apply
```

### Kubernetes Monitoring

```bash
# Watch deployments
watch kubectl get pods -n nextcloud

# Check events
kubectl get events -n nextcloud

# Monitor resource usage
kubectl top nodes
kubectl top pods -n nextcloud
```

### Pulumi Logging

```bash
# View operation logs
pulumi logs

# Export metrics
pulumi stack export
```

---

## Disaster Recovery

### Terraform Rollback

```bash
# View previous versions
terraform state list

# Rollback to previous state
terraform state pull > backup.state
# Edit terraform.tfstate to revert

# Or use terraform.tfvars to trigger rollback
terraform apply
```

### Ansible Playbook Rollback

```bash
# Create rollback playbook
ansible-playbook -i inventory-prod.yml rollback.yml
```

### Kubernetes Rollback

```bash
# View deployment history
kubectl rollout history deployment/nextcloud -n nextcloud

# Rollback to previous version
kubectl rollout undo deployment/nextcloud -n nextcloud

# Rollback to specific revision
kubectl rollout undo deployment/nextcloud -n nextcloud --to-revision=2
```

---

## Security Best Practices

### Terraform

```hcl
# ✅ DO: Use sensitive variables for secrets
variable "db_password" {
  type      = string
  sensitive = true
}

# ✅ DO: Enable encryption
backend "s3" {
  encrypt = true
}

# ✅ DO: Use IAM roles instead of keys
provider "aws" {
  assume_role {}
}
```

### Ansible

```yaml
# ✅ DO: Use vault for secrets
ansible_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  66...

# ✅ DO: Use become_user sparingly
become: yes
become_user: root

# ✅ DO: Validate SSL certificates
validate_certs: yes
```

### Kubernetes

```yaml
# ✅ DO: Use network policies
NetworkPolicy:
  policyTypes:
    - Ingress
    - Egress

# ✅ DO: Set resource limits
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"

# ✅ DO: Use secret management
secretKeyRef:
  name: nextcloud-secrets
```

---

## Troubleshooting

### Ansible Issues

```bash
# Connection timeout
ansible -i inventory-prod.yml all -m ping -vvv

# Permission denied
# Add SSH key
ssh-add ~/.ssh/your-key.pem

# Check inventory
ansible -i inventory-prod.yml all -m setup
```

### Terraform Issues

```bash
# State lock conflict
terraform force-unlock <LOCK_ID>

# Provider issues
terraform init -upgrade

# Debug
terraform console
```

### Kubernetes Issues

```bash
# Pod not starting
kubectl describe pod <POD_NAME> -n nextcloud

# Check logs
kubectl logs <POD_NAME> -n nextcloud

# Debug container
kubectl exec -it <POD_NAME> -n nextcloud -- /bin/bash
```

### Pulumi Issues

```bash
# Stack conflicts
pulumi stack rm --force

# Debug execution
pulumi up --debug

# Check logs
pulumi logs
```

---

## Support and Resources

- **Ansible**: https://docs.ansible.com/
- **Terraform**: https://registry.terraform.io/
- **Kubernetes**: https://kubernetes.io/docs/
- **Pulumi**: https://www.pulumi.com/docs/

---

**Last Updated**: March 15, 2024  
**Version**: 1.0.0  
**Status**: ✅ Production Ready
