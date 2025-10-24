#!/bin/bash

# Ubuntu RAG System Setup Script
# Bu script Ubuntu makineye gerekli tüm bağımlılıkları kurar

set -e

echo "🚀 Ubuntu RAG System Kurulumu Başlıyor..."

# Renkli output için
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log fonksiyonu
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Sistem güncellemesi
log "Sistem paketleri güncelleniyor..."
sudo apt update && sudo apt upgrade -y

# Gerekli paketlerin kurulumu
log "Gerekli paketler kuruluyor..."
sudo apt install -y \
    curl \
    wget \
    git \
    make \
    docker.io \
    containerd \
    jq \
    unzip \
    build-essential

# kubectl kurulumu (direkt binary olarak)
log "kubectl kuruluyor..."
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    log "✅ kubectl kuruldu"
else
    log "✅ kubectl zaten kurulu"
fi

# Docker servisini başlat ve etkinleştir
log "Docker servisi başlatılıyor..."
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# NVIDIA Container Toolkit kurulumu
log "NVIDIA Container Toolkit kuruluyor..."
if ! command -v nvidia-smi &> /dev/null; then
    warn "nvidia-smi bulunamadı. NVIDIA driver kurulu olmalı."
    warn "Lütfen önce NVIDIA driver'ı kurun: https://developer.nvidia.com/cuda-downloads"
fi

# NVIDIA Container Toolkit repository ekleme
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit

# containerd konfigürasyonu
log "containerd NVIDIA runtime konfigürasyonu yapılıyor..."
sudo nvidia-ctk runtime configure --runtime=containerd
sudo systemctl restart containerd

# Docker konfigürasyonu
log "Docker NVIDIA runtime konfigürasyonu yapılıyor..."
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# GitHub CLI kurulumu (opsiyonel)
log "GitHub CLI kuruluyor..."
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install -y gh

# K3s kurulumu
log "K3s kuruluyor..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
sudo systemctl enable k3s
sudo systemctl start k3s

# kubectl konfigürasyonu
log "kubectl konfigürasyonu yapılıyor..."
sudo mkdir -p /etc/rancher/k3s
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# K3s local-path storage class kontrolü
log "K3s local-path storage class kontrol ediliyor..."
kubectl get storageclass local-path || warn "local-path storage class bulunamadı"

# GPU test
log "GPU erişilebilirliği test ediliyor..."
if nvidia-smi > /dev/null 2>&1; then
    log "✅ GPU erişilebilir!"
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits
else
    warn "⚠️  GPU erişilebilir değil. NVIDIA driver kurulu olmalı."
fi

# Docker test
log "Docker test ediliyor..."
if docker run --rm hello-world > /dev/null 2>&1; then
    log "✅ Docker çalışıyor!"
else
    error "❌ Docker çalışmıyor!"
fi

# K3s test
log "K3s test ediliyor..."
if kubectl get nodes > /dev/null 2>&1; then
    log "✅ K3s çalışıyor!"
    kubectl get nodes
else
    error "❌ K3s çalışmıyor!"
fi

# .env dosyası kontrolü
log ".env dosyası kontrol ediliyor..."
if [ -f ".env" ]; then
    log "✅ .env dosyası mevcut"
else
    warn "⚠️  .env dosyası bulunamadı. .env.example'dan kopyalayın:"
    warn "   cp .env.example .env"
    warn "   Sonra .env dosyasını düzenleyin"
fi

log "🎉 Ubuntu RAG System kurulumu tamamlandı!"
log ""
log "📋 Sonraki adımlar:"
log "1. .env dosyasını düzenleyin (GITHUB_TOKEN ekleyin)"
log "2. make up komutunu çalıştırın"
log "3. make ui-argo ile ArgoCD arayüzüne erişin"
log ""
log "💡 Yardım için: make help"
