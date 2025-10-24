# Ubuntu RAG System

Bu proje, Ubuntu makine üzerinde K3s Kubernetes cluster'ı kullanarak çalışan bir RAG (Retrieval-Augmented Generation) sistemidir. Apache dökümanları üzerinde GPU destekli AI asistanı sağlar.

## 🏗️ Sistem Mimarisi

- **Backend**: FastAPI ile PDF işleme ve chat API
- **Frontend**: Streamlit ile kullanıcı arayüzü  
- **Qdrant**: Vektör veritabanı
- **Ollama**: GPU'da çalışan LLM (Qwen modeli)
- **ArgoCD**: GitOps ile deployment yönetimi
- **K3s**: Lightweight Kubernetes cluster

## 🚀 Hızlı Başlangıç

### 1. Sistem Gereksinimleri

- Ubuntu 20.04+ 
- NVIDIA GPU (CUDA destekli)
- En az 8GB RAM
- En az 20GB disk alanı

### 2. Kurulum

```bash
# 1. Repository'yi klonlayın
git clone https://github.com/peler1nl1kelt0s/rag-system.git
cd rag-system

# 2. .env dosyasını oluşturun
cp .env.example .env
# .env dosyasını düzenleyin (GITHUB_TOKEN ekleyin)

# 3. Ubuntu sistem kurulumu (ilk kez)
make setup-ubuntu

# 4. Docker image'larını build edin
make build-images

# 5. Tüm sistemi kurun
make up
```

### 3. Kullanım

```bash
# ArgoCD arayüzü
make ui-argo

# Streamlit arayüzü  
make ui-app

# PDF'leri yükle
make ingest
```

## 📋 Komutlar

```bash
# Temel komutlar
make up                    # Tüm sistemi kurar
make destroy              # K3s'i tamamen siler
make clean                # Sadece uygulamaları siler
make status               # Pod durumlarını gösterir

# Arayüzler
make ui-argo              # ArgoCD arayüzü
make ui-app               # Streamlit frontend

# Veri işlemleri
make ingest               # PDF'leri Qdrant'a yükler

# Kurulum
make setup-ubuntu         # Ubuntu sistem kurulumu
make install-k3s          # K3s kurulumu
make install-gpu-plugin   # NVIDIA GPU plugin
make check-gpu            # GPU kontrolü

# Build
make build-images         # Docker image'larını build eder
```

## ⚙️ Konfigürasyon

`.env` dosyasını düzenleyerek sistemi özelleştirebilirsiniz:

```bash
# GitHub Configuration
GITHUB_USER=your_username
GITHUB_TOKEN=your_token

# GPU Configuration  
MODEL_NAME=qwen

# Resource Limits
OLLAMA_MEMORY_LIMIT=4Gi
BACKEND_MEMORY_LIMIT=2Gi
```

## 🔧 Sorun Giderme

### GPU Sorunları
```bash
# GPU kontrolü
nvidia-smi
make check-gpu

# NVIDIA Container Toolkit kontrolü
nvidia-ctk --version
```

### K3s Sorunları
```bash
# K3s durumu
sudo systemctl status k3s
kubectl get nodes

# Log kontrolü
sudo journalctl -u k3s -f
```

### Pod Sorunları
```bash
# Pod durumları
make status

# Log kontrolü
kubectl logs -n rag-system deployment/rag-backend
kubectl logs -n rag-system deployment/rag-frontend
```

## 📚 Daha Fazla Bilgi

- [K3s Dokümantasyonu](https://k3s.io/)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/)
- [ArgoCD](https://argo-cd.readthedocs.io/)
- [Ollama](https://ollama.ai/)

## 🤝 Katkıda Bulunma

1. Fork yapın
2. Feature branch oluşturun (`git checkout -b feature/amazing-feature`)
3. Commit yapın (`git commit -m 'Add amazing feature'`)
4. Push yapın (`git push origin feature/amazing-feature`)
5. Pull Request oluşturun

## 📄 Lisans

Bu proje MIT lisansı altında lisanslanmıştır.