# CISC 886 - Cloud Computing Project
## InfoSec Chatbot: End-to-End Cloud-Based LLM Deployment on AWS

**Group members:** Marko Hanna - Aya Mohamed - Mohmoud Alsakhawy  
**NetID:** Group 1  
**Course:** CISC 886 - Cloud Computing, Queen's University  
**Model:** `unsloth/Llama-3.2-1B-Instruct` fine-tuned with QLoRA  
**Domain:** Information Security Q&A  

---

## Project Overview

This project deploys a fine-tuned large language model as a cloud-based chat assistant on AWS. The system:

1. Preprocesses a custom InfoSec Q&A dataset using **Apache Spark on AWS EMR**
2. Fine-tunes **Llama-3.2-1B-Instruct** using **QLoRA (Unsloth)** on Google Colab
3. Serves the fine-tuned model via **Ollama** on an **AWS EC2** (`m4.xlarge`) instance
4. Provides a browser-based chat interface via **OpenWebUI** on port 3000
5. All AWS infrastructure is provisioned using **Terraform**

---

## Repository Structure

```
.
├── README.md
├── Screenshots/                     
├── dataset/
│   ├── infosec_dataset.jsonl       
│   ├── infosec_train.jsonl         
│   ├── infosec_val.jsonl            
│   └── infosec_test.jsonl           
├── preprocessing/
│   └── preprocess.py               
├── finetuning/
│   └── infosec_finetuning.ipynb   
    └── Final_Output.png
├── terraform/
│   ├── provider.tf              
│   ├── variables.tf                
│   ├── vpc.tf                      
│   ├── ec2.tf                      
│   └── outputs.tf                 
├── deployment/
    ├── ec2_deploy.sh           
    ├── ollama.service              
    └── verify_autostart.sh         

```

---

## Prerequisites

Before starting, ensure you have:

| Tool | Version | Purpose |
|---|---|---|
| AWS Account | root account | All cloud resources |
| Terraform | >= 1.5.0 | Infrastructure provisioning |
| Python | >= 3.10 | Running local scripts |
| Git | Any | Cloning this repository |
| Google Account | Any | Google Colab fine-tuning |
| Hugging Face Account | Any | Storing GGUF model |
| SSH key pair | EC2 key pair | Accessing EC2 instance |

**AWS Services used:** S3, EMR, EC2 (custom security group), VPC (routing table, subnet, internet gatway) 
**AWS Region:** `us-east-1` (all resources must be in the same region)

---

## Phase 1 - Dataset Preparation

### 1.1 Clone this repository

```bash
git clone https://github.com/mahmoudalsakhawy/group1-cisc886-project.git
cd group1-cisc886-project
```

### 1.2 Upload dataset to S3

Create the S3 bucket (replace `group1`):

```bash
aws s3 mb s3://group1-infosec-bucket --region us-east-1
```

Upload dataset files:

```bash
aws s3 cp dataset/infosec_dataset.jsonl s3://group1-infosec-bucket/input/
aws s3 cp dataset/infosec_train.jsonl   s3://group1-infosec-bucket/input/
aws s3 cp dataset/infosec_val.jsonl     s3://group1-infosec-bucket/input/
aws s3 cp dataset/infosec_test.jsonl    s3://group1-infosec-bucket/input/
aws s3 cp preprocessing/preprocess.py  s3://group1-infosec-bucket/scripts/
```

Verify uploads:

```bash
aws s3 ls s3://group1-infosec-bucket/input/
aws s3 ls s3://group1-infosec-bucket/scripts/
```

---

## Phase 2 - Data Preprocessing on AWS EMR

### 2.1 Edit the preprocessing script

Open `preprocessing/preprocess.py` which includes: 

```python
S3_BUCKET = "group1-infosec-bucket"
NETID     = "group1"
```

Upload after verifying:

```bash
aws s3 cp preprocessing/preprocess.py s3://group1-infosec-bucket/scripts/
```

### 2.2 Launch EMR Cluster

```bash
aws emr create-cluster \
  --name "group1-emr-infosec" \
  --release-label emr-7.1.0 \
  --applications Name=Spark \
  --instance-type m4.xlarge \
  --instance-count 2 (1 Core, 1 primary) \
  --use-default-roles \
  --region us-east-1 \
  --log-uri s3://group1-infosec-bucket/emr-logs/
```


Wait for cluster to reach **Waiting** state (~5 minutes):
note your ClusterId: (eg. j-your_cluster_id)

### 2.3 Submit the PySpark Step

```bash
aws emr add-steps \
  --cluster-id j-your_cluster_id \
  --steps Type=Spark,Name="group1-preprocess-step",\
ActionOnFailure=CONTINUE,\
Args=[s3://group1-infosec-bucket/scripts/preprocess.py]
```

Monitor step until **COMPLETED**:


### 2.4 Verify S3 output

```bash
aws s3 ls s3://group1-infosec-bucket/output/
aws s3 ls s3://group1-infosec-bucket/figures/
```

You should see `train/`, `val/`, `test/`, `full/` folders in the 'Output/' folder and 3 PNG figures in the 'figures/' folder.

### 2.5 Download EDA figures

```bash
aws s3 cp s3://group1-infosec-bucket/figures/ ./figures/ --recursive
```

### 2.6 Terminate the EMR cluster 

```bash
aws emr terminate-clusters --cluster-ids j-your_cluster_id
```

Verify termination:

```bash
aws emr describe-cluster --cluster-id j-your_cluster_id \
  --query 'Cluster.Status.State'
```


---

## Phase 3 - Model Fine-Tuning (Google Colab)

### 3.1 Open the notebook

1. Go to [colab.research.google.com](https://colab.research.google.com)
2. Upload `finetuning/infosec_finetuning.ipynb`
3. **Runtime → Change runtime type → T4 GPU** (required)

### 3.2 Upload dataset files to Colab

When Cell 7 prompts you, upload:
- `dataset/infosec_train.jsonl`
- `dataset/infosec_val.jsonl`

### 3.3 Run all cells top to bottom

Expected outcomes per cell:

| Cell | Expected Output |
|---|---|
| 1 - GPU check | `Tesla T4` visible |
| 2 - Install | No errors after ~3 minutes |
| 5 - Load model | `Model loaded: unsloth/Llama-3.2-1B-Instruct` |
| 6 - LoRA | `Trainable parameters: ~X,XXX,XXX (1-2%)` |
| 8 - Train | Loss decreasing from ~2.0 to ~0.5 over 3 epochs |
| 9 - Loss curve | Plot displayed and saved |
| 10 - Compare | Fine-tuned responses more focused than base |
| 12 - GGUF export | `unsloth.Q8_0.gguf` file ~1.3 GB |
| 13 - HF upload | URL to your HF repo printed |

### 3.4 Configure Hugging Face token

Before running Cell 13:
1. Go to [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens)
2. Create a new token with **Write** access
3. In Colab: go to the Secrets panel (left sidebar) → add `HF_TOKEN`

### 3.5 Download outputs

Cell 14 downloads:
- `training_loss_curve.png` - include in your report
- `infosec-lora.zip` - commit to GitHub under `finetuning/`

---

## Phase 4 - Infrastructure Provisioning (Terraform)

### 4.1 Install Terraform


**Windows:** Download from [developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads)

Verify:
```bash
terraform --version
```

### 4.2 Set AWS credentials

Copy credentials from your AWS Academy Learner Lab panel:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

### 4.3 Edit variables.tf

Open `terraform/variables.tf` and update:

```hcl
variable "netid"         { default = "group1" }
variable "my_ip"         { default = "IP.ADDRESS/32" } 
variable "key_pair_name" { default = "group1-keypair" }
```

Find your AWS IP ADDRESS at: [checkip.amazonaws.com](https://checkip.amazonaws.com)

### 4.4 Apply Terraform

```bash
cd terraform/
terraform init
terraform plan    
terraform apply     # type 'yes' when prompted
```

Save the output - it contains your EC2 IP and URLs:

```
ec2_public_ip  = "54.X.X.X"
openwebui_url  = "http://54.X.X.X:3000"
ssh_command    = "ssh -i ~/.ssh/group1-keypair.pem ec2-user@54.X.X.X"
```

---

## Phase 5 - Model Deployment on EC2

### 5.1 SSH into the instance

```bash
chmod 400 ~/.ssh/group1-keypair.pem
ssh -i ~/.ssh/group1-keypair.pem ec2-user@YOUR_EC2_IP
```

### 5.2 Wait for bootstrap to complete

```bash
sudo tail -f /var/log/user-data.log
```

### 5.3 Download your GGUF model

```bash
mkdir -p /home/ec2-user/models && cd /home/ec2-user/models

wget "https://huggingface.co/Mahmoud-Alsakhawy/infosec-llama3-qlora-gguf/resolve/main/llama-3.2-1b-instruct.Q8_0.gguf" \
     -O infosec-llama3.gguf --progress=bar:force
```

### 5.4 Create Modelfile

```bash
cat > /home/ec2-user/models/Modelfile <<'EOF'
FROM ./infosec-llama3.gguf

SYSTEM """
You are a knowledgeable and helpful information security expert.
Answer questions clearly, accurately, and concisely.
"""

PARAMETER temperature 0.1
PARAMETER num_predict 256
PARAMETER stop "<|eot_id|>"
PARAMETER stop "<|end_of_text|>"
EOF
```

### 5.5 Register model with Ollama

```bash
cd /home/ec2-user/models
ollama create infosec-assistant -f Modelfile
ollama list
```

### 5.6 Test with curl 

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

## Phase 6 - Web Interface (OpenWebUI)

### 6.1 Access OpenWebUI

Open in your browser:
```
http://YOUR_EC2_IP:3000
```

### 6.2 First-time setup

1. Create an admin account (any email/password)
2. Click the model selector dropdown at the top
3. Select **infosec-assistant**
4. Type a question and verify the model responds

### 6.3 Verify auto-start after reboot

```bash
sudo reboot

bash /path/to/verify_autostart.sh
```

---

## AWS Cost Summary



| Service | Resource | Usage | Approx. Cost |
|---|---|---|---|
| **S3** | `group1-infosec-bucket` | ~50 MB storage + transfers | ~$0.01 |
| **EMR** | 2x `m4.xlarge`, ~30 min | Cluster + EC2 costs | ~$0.45 |
| **EC2** | `m4.xlarge` | ~10 hours total usage | ~$5.26 |
| **EC2 EBS** | 100 GB `gp3` volume | Per month | ~$0.80 |
| **Data Transfer** | HF model download, apt | ~3 GB outbound | ~$0.27 |
| **Total** | | | **~$6.79** |


---

## Cleanup 

Run these to avoid unnecessary charges:

```bash
# Destroy all Terraform-managed resources
cd terraform/
terraform destroy

# Empty and delete S3 bucket
aws s3 rm s3://group1-infosec-bucket --recursive
aws s3 rb s3://group1-infosec-bucket
```

---

