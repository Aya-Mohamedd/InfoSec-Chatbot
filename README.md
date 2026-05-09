# CISC 886 - Cloud Computing Project
## InfoSec Chatbot: End-to-End Cloud-Based LLM Deployment on AWS

**Group members:**  Aya Mohamed - Mahmoud Alsakhawy - Marko Hanna 
**NetID:** Group 1  
**Model:** `unsloth/Llama-3.2-1B-Instruct` fine-tuned with QLoRA  
**Domain:** Information Security Q&A  

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Repository Structure](#repository-structure)
4. [Prerequisites](#prerequisites)
5. [Phase 1 — Dataset Preparation](#phase-1--dataset-preparation)
6. [Phase 2 — Data Preprocessing on AWS EMR](#phase-2--data-preprocessing-on-aws-emr)
7. [Phase 3 — Model Fine-Tuning on Google Colab](#phase-3--model-fine-tuning-on-google-colab)
8. [Phase 4 — Infrastructure Provisioning with Terraform](#phase-4--infrastructure-provisioning-with-terraform)
9. [Phase 5 — Model Deployment on EC2](#phase-5--model-deployment-on-ec2)
10. [Phase 6 — Web Interface via OpenWebUI](#phase-6--web-interface-via-openwebui)
11. [AWS Cost Summary](#aws-cost-summary)
12. [Cleanup](#cleanup)

---

## Project Overview

This project implements a fully cloud-native pipeline for fine-tuning and serving a large language model (LLM) specialized in Information Security Q&A. The system is designed around six distinct phases, each leveraging dedicated AWS services:

| Phase | Description | Technology |
|-------|-------------|------------|
| 1 | Dataset preparation and upload | AWS S3 |
| 2 | Data preprocessing and EDA | Apache Spark on AWS EMR |
| 3 | Model fine-tuning | QLoRA (Unsloth) on Google Colab |
| 4 | Infrastructure provisioning | Terraform |
| 5 | Model serving | Ollama on AWS EC2 (`m4.xlarge`) |
| 6 | User interface | OpenWebUI on port 3000 |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                        AWS (us-east-1)                  │
│                                                         │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │  AWS S3  │───▶│  AWS EMR     │───▶│   AWS EC2     │  │
│  │ (Dataset)│    │ (PySpark EDA)│    │ (Ollama +     │  │
│  └──────────┘    └──────────────┘    │  OpenWebUI)   │  │
│                                      └───────────────┘  │
│                        ▲                    ▲            │
│                        │                   │            │
│              Terraform provisions  User accesses :3000  │
└─────────────────────────────────────────────────────────┘
                         ▲
              ┌──────────────────────┐
              │  Google Colab (T4)   │
              │  QLoRA fine-tuning   │
              │  → GGUF export       │
              │  → Hugging Face Hub  │
              └──────────────────────┘
```

---

## Repository Structure

```
.
├── README.md
├── Screenshots/
├── dataset/
│   ├── infosec_dataset.jsonl       # Full InfoSec Q&A dataset
│   ├── infosec_train.jsonl         # Training split
│   ├── infosec_val.jsonl           # Validation split
│   └── infosec_test.jsonl          # Test split
├── preprocessing/
│   └── preprocess.py               # PySpark preprocessing + EDA script
├── finetuning/
│   ├── infosec_finetuning.ipynb    # Colab fine-tuning notebook
│   └── Final_Output.png
├── terraform/
│   ├── provider.tf
│   ├── variables.tf
│   ├── vpc.tf                      # VPC, subnet, internet gateway, routing
│   ├── ec2.tf                      # EC2 instance + security group
│   └── outputs.tf
└── deployment/
    ├── ec2_deploy.sh               # Bootstrap and deployment script
    ├── ollama.service              # systemd service for Ollama
    └── verify_autostart.sh         # Post-reboot validation script
```

---

## Prerequisites

Ensure all of the following tools and accounts are available before proceeding.

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | Any | Interacting with AWS services |
| Terraform | ≥ 1.5.0 | Infrastructure provisioning |
| Python | ≥ 3.10 | Running local scripts |
| Git | Any | Cloning this repository |

### Required Accounts

| Account | Purpose |
|---------|---------|
| AWS (root) | All cloud resources |
| Google | Google Colab fine-tuning |
| Hugging Face | Hosting the exported GGUF model |

### AWS Services & Region

- **Services used:** S3, EMR, EC2, VPC (subnet, routing table, internet gateway)
- **Region:** `us-east-1` — all resources must be deployed in the same region
- **EC2 key pair:** Required for SSH access to the instance

---

## Phase 1 — Dataset Preparation

### 1.1 Clone the Repository

```bash
git clone https://github.com/mahmoudalsakhawy/group1-cisc886-project.git
cd group1-cisc886-project
```

### 1.2 Create the S3 Bucket and Upload Dataset

Create the S3 bucket (replace `group1` with your group identifier if needed):

```bash
aws s3 mb s3://group1-infosec-bucket --region us-east-1
```

Upload all dataset and script files:

```bash
aws s3 cp dataset/infosec_dataset.jsonl  s3://group1-infosec-bucket/input/
aws s3 cp dataset/infosec_train.jsonl    s3://group1-infosec-bucket/input/
aws s3 cp dataset/infosec_val.jsonl      s3://group1-infosec-bucket/input/
aws s3 cp dataset/infosec_test.jsonl     s3://group1-infosec-bucket/input/
aws s3 cp preprocessing/preprocess.py   s3://group1-infosec-bucket/scripts/
```

Verify the uploads:

```bash
aws s3 ls s3://group1-infosec-bucket/input/
aws s3 ls s3://group1-infosec-bucket/scripts/
```

---

## Phase 2 — Data Preprocessing on AWS EMR

### 2.1 Update and Re-upload the Preprocessing Script

Verify that the following constants in `preprocessing/preprocess.py` match your setup:

```python
S3_BUCKET = "group1-infosec-bucket"
NETID     = "group1"
```

Re-upload after confirming:

```bash
aws s3 cp preprocessing/preprocess.py s3://group1-infosec-bucket/scripts/
```

### 2.2 Launch the EMR Cluster

```bash
aws emr create-cluster \
  --name "group1-emr-infosec" \
  --release-label emr-7.1.0 \
  --applications Name=Spark \
  --instance-type m4.xlarge \
  --instance-count 2 \
  --use-default-roles \
  --region us-east-1 \
  --log-uri s3://group1-infosec-bucket/emr-logs/
```

> Wait for the cluster to reach the **Waiting** state (~5 minutes). Note the returned `ClusterId` (e.g., `j-XXXXXXXXXXXX`).

### 2.3 Submit the PySpark Step

```bash
aws emr add-steps \
  --cluster-id j-YOUR_CLUSTER_ID \
  --steps Type=Spark,Name="group1-preprocess-step",\
ActionOnFailure=CONTINUE,\
Args=[s3://group1-infosec-bucket/scripts/preprocess.py]
```

Monitor the step status until it shows **COMPLETED** in the AWS Console or via the CLI.

### 2.4 Verify S3 Output

```bash
aws s3 ls s3://group1-infosec-bucket/output/
aws s3 ls s3://group1-infosec-bucket/figures/
```

Expected output structure:
- `output/` → `train/`, `val/`, `test/`, `full/` subdirectories
- `figures/` → 3 PNG EDA plots

### 2.5 Download EDA Figures

```bash
aws s3 cp s3://group1-infosec-bucket/figures/ ./figures/ --recursive
```

### 2.6 Terminate the EMR Cluster

```bash
aws emr terminate-clusters --cluster-ids j-YOUR_CLUSTER_ID
```

Confirm termination:

```bash
aws emr describe-cluster \
  --cluster-id j-YOUR_CLUSTER_ID \
  --query 'Cluster.Status.State'
```

---

## Phase 3 — Model Fine-Tuning on Google Colab

### 3.1 Open the Notebook

1. Navigate to [colab.research.google.com](https://colab.research.google.com)
2. Upload `finetuning/infosec_finetuning.ipynb`
3. Go to **Runtime → Change runtime type** and select **T4 GPU**

### 3.2 Upload Dataset Files

When Cell 7 prompts for file upload, provide:
- `dataset/infosec_train.jsonl`
- `dataset/infosec_val.jsonl`

### 3.3 Configure the Hugging Face Token

Before running Cell 13:
1. Visit [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens)
2. Generate a new token with **Write** access
3. In Colab, open the **Secrets** panel (left sidebar) and add `HF_TOKEN`

### 3.4 Execute All Cells in Order

| Cell | Expected Outcome |
|------|-----------------|
| 1 — GPU check | `Tesla T4` detected |
| 2 — Install dependencies | No errors (~3 minutes) |
| 5 — Load model | `Model loaded: unsloth/Llama-3.2-1B-Instruct` |
| 6 — Apply LoRA | ~1–2% trainable parameters |
| 8 — Train | Loss decreasing from ~2.0 → ~0.5 over 3 epochs |
| 9 — Loss curve | Plot displayed and saved |
| 10 — Compare outputs | Fine-tuned responses more domain-focused |
| 12 — Export GGUF | `unsloth.Q8_0.gguf` (~1.3 GB) |
| 13 — Upload to HF | Hugging Face repo URL printed |

### 3.5 Download Training Artifacts

Cell 14 produces two outputs to save locally:
- `training_loss_curve.png` — include in your project report
- `infosec-lora.zip` — commit to the repository under `finetuning/`

---

## Phase 4 — Infrastructure Provisioning with Terraform

### 4.1 Install Terraform

- **macOS/Linux:** Use the [official installer](https://developer.hashicorp.com/terraform/downloads) or a package manager
- **Windows:** Download from [developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads)

Verify the installation:

```bash
terraform --version
```

### 4.2 Export AWS Credentials

Copy the credentials from your AWS Academy Learner Lab panel:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

### 4.3 Configure `variables.tf`

Open `terraform/variables.tf` and update the following values:

```hcl
variable "netid"         { default = "group1" }
variable "my_ip"         { default = "YOUR.IP.ADDRESS/32" }
variable "key_pair_name" { default = "group1-keypair" }
```

> Your public IP can be found at [checkip.amazonaws.com](https://checkip.amazonaws.com).

### 4.4 Apply the Terraform Configuration

```bash
cd terraform/
terraform init
terraform plan     # Review the planned changes
terraform apply    # Type 'yes' when prompted
```

Save the output — it contains your instance's IP and access URLs:

```
ec2_public_ip  = "54.X.X.X"
openwebui_url  = "http://54.X.X.X:3000"
ssh_command    = "ssh -i ~/.ssh/group1-keypair.pem ec2-user@54.X.X.X"
```

---

## Phase 5 — Model Deployment on EC2

### 5.1 Connect to the Instance

```bash
chmod 400 ~/.ssh/group1-keypair.pem
ssh -i ~/.ssh/group1-keypair.pem ec2-user@YOUR_EC2_IP
```

### 5.2 Wait for Bootstrap to Complete

```bash
sudo tail -f /var/log/user-data.log
```

### 5.3 Download the Fine-Tuned GGUF Model

```bash
mkdir -p /home/ec2-user/models && cd /home/ec2-user/models

wget "https://huggingface.co/Mahmoud-Alsakhawy/infosec-llama3-qlora-gguf/resolve/main/llama-3.2-1b-instruct.Q8_0.gguf" \
     -O infosec-llama3.gguf --progress=bar:force
```

### 5.4 Create the Ollama Modelfile

```bash
cat > /home/ec2-user/models/Modelfile <<'EOF'
FROM ./infosec-llama3.gguf

SYSTEM """
You are a knowledgeable and helpful information security expert.
Answer questions clearly, accurately, and concisely.
"""

PARAMETER temperature  0.1
PARAMETER num_predict  256
PARAMETER stop         "<|eot_id|>"
PARAMETER stop         "<|end_of_text|>"
EOF
```

### 5.5 Register the Model with Ollama

```bash
cd /home/ec2-user/models
ollama create infosec-assistant -f Modelfile
ollama list
```

### 5.6 Test the Model via cURL

```bash
curl -s http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "infosec-assistant",
    "prompt": "What is a man-in-the-middle attack and how can it be prevented?",
    "stream": false
  }' | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('Model    :', data.get('model'))
print('Response :', data.get('response'))
"
```

---

## Phase 6 — Web Interface via OpenWebUI

### 6.1 Access the Interface

Open the following URL in your browser (replace with your EC2 public IP):

```
http://YOUR_EC2_IP:3000
```

### 6.2 Initial Setup

1. Create an admin account using any email and password
2. Open the model selector dropdown at the top of the chat interface
3. Select **infosec-assistant**
4. Submit a test query to confirm the model is responding correctly

### 6.3 Verify Auto-Start After Reboot

```bash
sudo reboot

# After the instance restarts:
bash /path/to/verify_autostart.sh
```

---

## AWS Cost Summary

| Service | Resource | Usage | Estimated Cost |
|---------|----------|-------|----------------|
| S3 | `group1-infosec-bucket` | ~50 MB storage + transfers | ~$0.01 |
| EMR | 2× `m4.xlarge`, ~30 min | Cluster + EC2 costs | ~$0.45 |
| EC2 | `m4.xlarge` | ~10 hours total | ~$5.26 |
| EBS | 100 GB `gp3` volume | Per month | ~$0.80 |
| Data Transfer | HF model download, apt | ~3 GB outbound | ~$0.27 |
| **Total** | | | **~$6.79** |

---

## Cleanup

Run the following commands after completing the project to avoid ongoing charges:

```bash
# Destroy all Terraform-managed AWS resources
cd terraform/
terraform destroy

# Remove all objects from the S3 bucket, then delete it
aws s3 rm s3://group1-infosec-bucket --recursive
aws s3 rb s3://group1-infosec-bucket
```

> **Note:** Ensure the EMR cluster has been terminated (Phase 2.6) before running `terraform destroy`.
