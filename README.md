# Multi-Cloud High-Availability Gateway: AWS (EKS) + Azure (AKS)

## 📖 Project Overview

This project demonstrates a **Zero-Touch Multi-Cloud Infrastructure** designed for high availability and disaster recovery. It provisions managed Kubernetes clusters on both **AWS (EKS)** and **Azure (AKS)** using Terraform, deploys a containerized Flask application to both, and orchestrates an **Nginx Reverse Proxy** as a single entry point that load-balances traffic across both cloud providers.

### Key Features

- **Cloud-Agnostic Deployment:** Identical workloads running on EKS (N. Virginia) and AKS (East US).
- **Automated Gateway Configuration:** A custom orchestration script fetches dynamic Cloud Load Balancer endpoints and reconfigures Nginx remotely via SSH.
- **Passive Health Checks:** Nginx is configured to detect failures in one cloud and automatically reroute 100% of traffic to the healthy provider.
- **Infrastructure as Code (IaC):** Full automation of VPCs, VNets, and managed K8s clusters using Terraform modules.

---

## 🏗️ Architecture

The system consists of three distinct layers:

- **Workload Layer:** A Flask-based Python application containerized with Docker.
- **Orchestration Layer:** Managed Kubernetes clusters (EKS & AKS) spanning two different global regions.
- **Traffic Layer:** An EC2-based Nginx instance acting as a Layer 7 Load Balancer.

---

## 🛠️ Tech Stack

| Category        | Tool                              |
|-----------------|-----------------------------------|
| Infrastructure  | Terraform                         |
| Clouds          | AWS (us-east-1), Azure (East US)  |
| Containerization| Docker                            |
| Orchestration   | Kubernetes (EKS v1.30, AKS)       |
| Web Server      | Nginx (Reverse Proxy)             |
| Language        | Python (Flask)                    |

---

## 🚀 Deployment Steps

### 1. Prerequisites

- AWS CLI & Azure CLI configured with admin permissions.
- Terraform installed.
- SSH key pair generated (`mc-key` and `mc-key.pub`) in the project root.

### 2. Infrastructure Provisioning

Initialize and apply the Terraform configuration:

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 3. Application Deployment

Apply the Kubernetes manifests to both clusters using their specific contexts:

```bash
# Deploy to AWS EKS
kubectl apply -f k8s/deployment.yaml --context=arn:aws:eks:us-east-1:[ACCOUNT_ID]:cluster/multi-cloud-eks
kubectl set env deployment/python-app CLOUD_PROVIDER=AWS_EKS --context=[AWS_CONTEXT]

# Deploy to Azure AKS
kubectl apply -f k8s/deployment.yaml --context=multi-cloud-aks
kubectl set env deployment/python-app CLOUD_PROVIDER=Azure_AKS --context=multi-cloud-aks
```

### 4. Nginx Bridge Configuration

Run the automation script to link the Cloud Load Balancers to the Nginx Gateway:

```bash
bash configure_nginx.sh
```

---

## ⚠️ Challenges Faced & Solutions

### 1. The "Host Untrusted" Error

**Problem:** The application returned `Host 'my_app' is not trusted`. This occurred because Nginx was passing its internal upstream name as the `Host` header, which the cloud backends rejected.

**Solution:** Updated the Nginx configuration to preserve the original host header and forward the client's real IP:

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
```

### 2. Upstream Variable Expansion in Remote Shells

**Problem:** The automation script failed with `host not found in upstream "max_fails=3"`. Local shell expansion was stripping out the AWS/Azure URLs before the config reached the server.

**Solution:** Implemented a hybrid "Safe-Mode" heredoc. We allowed local expansion for the Cloud URLs while using triple-backslashes (`\\\$`) to escape Nginx's internal variables (like `$host`) so they remained intact on the remote server.

---

## 🧹 Teardown & Ghost Check

To avoid surprise billing, resources must be deleted in order:

```bash
# 1. Delete K8s Services (Releases expensive Cloud Load Balancers)
kubectl delete -f k8s/deployment.yaml --context=[AWS_CONTEXT]
kubectl delete -f k8s/deployment.yaml --context=multi-cloud-aks

# 2. Destroy Infrastructure
cd terraform
terraform destroy -auto-approve
```

### Post-Teardown Verification

Always check for unmanaged "ghost" resources via CLI:

```bash
# Check AWS for unattached Load Balancers or EBS Volumes
aws elbv2 describe-load-balancers --region us-east-1
aws ec2 describe-volumes --region us-east-1 --filters Name=status,Values=available
```
