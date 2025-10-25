# 🚀 RAG AI Assistant - GPU-Enabled K3s System

GPU-enabled, Kubernetes-based RAG (Retrieval-Augmented Generation) system running on Apache documentation.

## 📋 Table of Contents

- [System Architecture](#-system-architecture)
- [Features](#-features)
- [Requirements](#-requirements)
- [Quick Start](#-quick-start)
- [Usage](#-usage)
- [Commands](#-commands)
- [Configuration](#️-configuration)
- [Troubleshooting](#-troubleshooting)
- [Project Structure](#-project-structure)

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    K3s Kubernetes Cluster                    │
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Frontend   │  │   Backend    │  │    Qdrant    │      │
│  │  (Streamlit) │◄─┤   (FastAPI)  │◄─┤   (Vector    │      │
│  │              │  │              │  │   Database)  │      │
│  └──────────────┘  └──────┬───────┘  └──────────────┘      │
│                           │                                  │
│                           ▼                                  │
│                    ┌──────────────┐                         │
│                    │    Ollama    │                         │
│                    │  (GPU + LLM) │                         │
│                    │   Qwen Model │                         │
│                    └──────────────┘                         │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              ArgoCD (GitOps Deployment)               │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Components

| Component | Technology | Description |
|-----------|------------|-------------|
| **Frontend** | Streamlit | User interface and chat interface |
| **Backend** | FastAPI | PDF processing, RAG pipeline, API |
| **Vector DB** | Qdrant | Vector database for document embeddings |
| **LLM** | Ollama (Qwen) | Language model running on GPU |
| **Orchestration** | K3s | Lightweight Kubernetes cluster |
| **GitOps** | ArgoCD | Automatic deployment and synchronization |
| **GPU Plugin** | NVIDIA Device Plugin | GPU access in Kubernetes |

---

## ✨ Features

- ✅ **GPU Enabled**: Fast LLM inference on NVIDIA GPU
- ✅ **Kubernetes Native**: Production-ready deployment with K3s
- ✅ **GitOps**: Automatic deployment with ArgoCD
- ✅ **Vector Search**: Semantic search with Qdrant
- ✅ **RAG Pipeline**: Intelligent Q&A on PDF documents
- ✅ **Auto Ingest**: PDFs automatically loaded on startup
- ✅ **Persistent Storage**: Qdrant data stored persistently
- ✅ **Modern UI**: User-friendly interface with Streamlit

---

## 🔧 Requirements

### Hardware
- **GPU**: NVIDIA GPU (CUDA-enabled)
- **RAM**: Minimum 8GB (16GB+ recommended)
- **Disk**: Minimum 20GB free space
- **CPU**: 4+ cores recommended

### Software
- **OS**: Ubuntu 20.04+ (or Debian-based)
- **NVIDIA Driver**: 525.x or higher
- **CUDA**: 12.0+ (comes with driver)
- **Git**: For version control

### Components to be Installed (Makefile installs automatically)
- K3s (Lightweight Kubernetes)
- kubectl (Kubernetes CLI)
- NVIDIA Container Toolkit
- ArgoCD

---

## 🚀 Quick Start

### 1️⃣ Clone the Repository

```bash
git clone https://github.com/peler1nl1kelt0s/rag-system.git
cd rag-system
```

### 2️⃣ Create Environment File

```bash
# Create .env file
cat > .env << 'EOF'
# GitHub Configuration (Required for private repo)
GITHUB_USER=your_github_username
GITHUB_TOKEN=your_github_personal_access_token

# Model Configuration
MODEL_NAME=qwen

# Resource Limits
OLLAMA_MEMORY_LIMIT=12Gi
BACKEND_MEMORY_LIMIT=2Gi
EOF
```

> **Note**: For GitHub Token:
> 1. GitHub → Settings → Developer Settings → Personal Access Tokens → Tokens (classic)
> 2. Grant `repo` and `read:packages` permissions
> 3. Add token to `.env` file

### 3️⃣ Install the System

```bash
# Install entire system with one command (K3s + GPU + ArgoCD + RAG)
make up
```

This command will:
1. ✅ Install K3s Kubernetes cluster
2. ✅ Install NVIDIA GPU plugin
3. ✅ Install ArgoCD
4. ✅ Create GitHub secrets
5. ✅ Deploy RAG application
6. ✅ Automatically load PDFs

**First installation may take 5-10 minutes.**

### 4️⃣ Access Interfaces

```bash
# Open Streamlit interface (RAG Chat)
make ui-app
# http://localhost:8501

# Open ArgoCD interface (Deployment management)
make ui-argo
# http://localhost:8080
# Username: admin
# Password: (shown in terminal)
```

---

## 🎮 Usage

### Chat Interface

1. **Open Streamlit interface**: `make ui-app`
2. **Ask questions**: Ask questions about Apache documentation
3. **Get answers**: Qwen model running on GPU provides answers

### Example Questions

```
- "What is the prototype of ft_substr function?"
- "What does ft_substr function do?"
- "What are the parameters of ft_substr?"
- "What is the return value of ft_substr?"
```

### PDF Loading

PDFs are placed in `apps/backend/apache_pdfs/` folder and automatically loaded when the system starts.

```bash
# To add new PDFs:
1. Copy PDF to apps/backend/apache_pdfs/ folder
2. Restart backend pod:
   kubectl rollout restart deployment/rag-backend -n rag-system
```

---

## 📋 Commands

### Main Commands

```bash
make up              # Install entire system (K3s + GPU + ArgoCD + RAG)
make down            # Remove entire system (including K3s)
make status          # Show pod statuses
make help            # Show help menu
```

### Interface Commands

```bash
make ui-argo         # Open ArgoCD interface (port 8080)
make ui-app          # Open Streamlit interface (port 8501)
```

### Installation Steps (Manual)

Normally `make up` does all of this, but for manual installation:

```bash
make install-k3s           # Install K3s
make configure-k3s         # Configure K3s
make install-gpu-plugin    # Install NVIDIA GPU plugin
make install-argocd        # Install ArgoCD
make create-secrets        # Create GitHub secrets
make deploy-app            # Deploy RAG application
```

---

## ⚙️ Configuration

### Environment Variables (.env)

```bash
# GitHub Configuration
GITHUB_USER=your_username          # Your GitHub username
GITHUB_TOKEN=ghp_xxxxxxxxxxxxx     # GitHub Personal Access Token

# Model Configuration
MODEL_NAME=qwen                    # LLM model to use

# Resource Limits
OLLAMA_MEMORY_LIMIT=12Gi          # Memory limit for Ollama
BACKEND_MEMORY_LIMIT=2Gi          # Memory limit for Backend
```

### Makefile Variables

```makefile
APP_NS        = rag-system         # Application namespace
ARGOCD_NS     = argocd            # ArgoCD namespace
ARGOCD_PORT   = 8080              # ArgoCD port
FRONTEND_PORT = 8501              # Streamlit port
```

### Backend Environment (manifests/04-backend.yaml)

```yaml
env:
- name: QDRANT_URL
  value: "http://qdrant-service.rag-system.svc.cluster.local:6333"
- name: OLLAMA_URL
  value: "http://ollama-service.rag-system.svc.cluster.local:11434"
- name: MODEL_NAME
  value: "qwen"
- name: COLLECTION_NAME
  value: "apache_docs"
- name: DATA_PATH
  value: "/data/"
```

---

## 🔍 Troubleshooting

### 1. K3s Not Starting

**Symptom**: `make up` command stuck at K3s installation

**Solution**:
```bash
# Check K3s service status
sudo systemctl status k3s

# Check K3s logs
sudo journalctl -u k3s -n 50 --no-pager

# Restart K3s
sudo systemctl restart k3s

# Check config file
ls -la /etc/rancher/k3s/k3s.yaml
```

### 2. GPU Not Recognized

**Symptom**: Ollama pod doesn't see GPU

**Solution**:
```bash
# Check GPU
nvidia-smi

# Check NVIDIA Container Toolkit
nvidia-ctk --version

# Check GPU plugin pods
kubectl get pods -n kube-system | grep nvidia

# Check GPU node label
kubectl get nodes -o json | jq '.items[].status.allocatable'
```

### 3. ArgoCD Sync Error

**Symptom**: ArgoCD application in "OutOfSync" state

**Solution**:
```bash
# Open ArgoCD interface
make ui-argo

# Manual sync (from UI or CLI)
kubectl get applications -n argocd

# Check secrets
kubectl get secrets -n argocd | grep github
kubectl get secrets -n rag-system | grep ghcr
```

### 4. Backend Pod CrashLoopBackOff

**Symptom**: Backend pod keeps restarting

**Solution**:
```bash
# Check backend logs
kubectl logs -n rag-system deployment/rag-backend

# Check if Qdrant and Ollama services are ready
kubectl get pods -n rag-system

# Restart backend pod
kubectl rollout restart deployment/rag-backend -n rag-system
```

### 5. Cannot Access Frontend

**Symptom**: `make ui-app` not working

**Solution**:
```bash
# Check if frontend pod is running
kubectl get pods -n rag-system | grep frontend

# Check service
kubectl get svc -n rag-system | grep frontend

# Start port-forward manually
kubectl port-forward svc/rag-frontend-service -n rag-system 8501:8501
```

### 6. Qdrant Data Lost

**Symptom**: Chat not working, "Qdrant database not ready" error

**Solution**:
```bash
# Check Qdrant pod
kubectl get pods -n rag-system | grep qdrant

# Check PVC
kubectl get pvc -n rag-system

# Restart backend (will auto ingest)
kubectl rollout restart deployment/rag-backend -n rag-system

# Follow logs
kubectl logs -n rag-system deployment/rag-backend -f
```

### 7. Complete System Reset

```bash
# Remove entire system
make down

# Clean .kube config
rm -rf ~/.kube

# Reinstall
make up
```

---

## 📁 Project Structure

```
rag-system/
├── apps/
│   ├── backend/                    # FastAPI backend
│   │   ├── apache_pdfs/           # PDF documents
│   │   │   └── en.subject.pdf
│   │   ├── Dockerfile             # Backend container
│   │   ├── main.py                # FastAPI application
│   │   └── requirements.txt       # Python dependencies
│   └── frontend/                   # Streamlit frontend
│       ├── Dockerfile             # Frontend container
│       ├── app.py                 # Streamlit application
│       └── requirements.txt       # Python dependencies
├── k3s-gpu/
│   └── device-plugin-daemonset.yaml  # NVIDIA GPU plugin
├── manifests/                      # Kubernetes manifests
│   ├── 01-namespaces.yaml         # Namespace definitions
│   ├── 02-qdrant.yaml             # Qdrant deployment
│   ├── 03-ollama-gpu.yaml         # Ollama GPU deployment
│   ├── 04-backend.yaml            # Backend deployment
│   ├── 05-frontend.yaml           # Frontend deployment
│   └── 06-argocd-app.yaml         # ArgoCD application
├── scripts/
│   ├── ubuntu-setup.sh            # Ubuntu system setup
│   └── force-sync.sh              # ArgoCD force sync
├── Makefile                        # Automation commands
├── README.md                       # This file
└── .env                           # Environment variables (to be created)
```

---

## 🔐 Security Notes

1. **GitHub Token**: Never commit `.env` file
2. **ArgoCD Password**: Change after first login
3. **Private Repo**: `ghcr-secret` required if images are in private repo
4. **Firewall**: Only open ports when necessary

---

## 📊 Performance Notes

### GPU Usage
- **Ollama**: ~4-8GB VRAM (depending on model size)
- **Inference**: ~100-500ms (depending on question complexity)

### Memory Usage
- **Ollama**: 8-12GB RAM
- **Backend**: 1-2GB RAM
- **Frontend**: 512MB-1GB RAM
- **Qdrant**: 500MB-2GB RAM (depending on data size)

### Disk Usage
- **K3s**: ~2GB
- **Docker Images**: ~5-8GB
- **Qdrant Data**: ~500MB-5GB (depending on document count)

---

## 🚀 Advanced

### Using Different Models

```bash
# Change MODEL_NAME in .env file
MODEL_NAME=llama2

# Restart Ollama pod
kubectl rollout restart deployment/ollama -n rag-system
```

### Adding More PDFs

```bash
# Add PDFs
cp your_pdfs/*.pdf apps/backend/apache_pdfs/

# Rebuild image (GitHub Actions does this automatically)
git add apps/backend/apache_pdfs/
git commit -m "Add new PDFs"
git push

# ArgoCD will auto sync
```

### Increasing Resource Limits

Edit `manifests/03-ollama-gpu.yaml`:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    memory: "16Gi"  # Increased
    cpu: "8"        # Increased
```

---

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Create Pull Request

---

## 📝 License

This project is licensed under the MIT License.

---

## 📞 Support

If you're experiencing issues:
1. Check [Troubleshooting](#-troubleshooting) section
2. Open an issue on GitHub
3. Include logs (`kubectl logs` outputs)

---

## 🎯 Roadmap

- [ ] Multi-user support
- [ ] React/Next.js instead of web UI
- [ ] More document formats (DOCX, TXT, MD)
- [ ] Chat history
- [ ] User authentication
- [ ] Cloud deployment (GKE, EKS, AKS)

---

**Created by**: peler1nl1kelt0s  
**Version**: 1.0.0  
**Last Updated**: 2025
