#!/bin/bash

# Docker Image Build Script for Ubuntu RAG System
# Bu script backend ve frontend Docker image'larını build eder

set -e

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

# .env dosyasını yükle
if [ -f ".env" ]; then
    source .env
    log ".env dosyası yüklendi"
else
    error ".env dosyası bulunamadı. Lütfen .env.example'dan kopyalayın"
fi

# GitHub Container Registry'ye login kontrolü
log "GitHub Container Registry login kontrol ediliyor..."
if ! docker info | grep -q "Username: $GITHUB_USER"; then
    if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "your_github_token_here" ]; then
        error "GITHUB_TOKEN .env dosyasında tanımlanmamış. Lütfen .env dosyasını düzenleyin."
    fi
    log "GitHub Container Registry'ye login yapılıyor..."
    echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin
    if [ $? -ne 0 ]; then
        error "GitHub Container Registry login başarısız!"
    fi
    log "✅ GitHub Container Registry login başarılı!"
fi

# Backend image build
log "Backend Docker image build ediliyor..."
cd apps/backend
docker build -t $IMAGE_REGISTRY/$IMAGE_REPOSITORY/rag-system-backend:$BACKEND_IMAGE_TAG .
log "✅ Backend image build edildi: $IMAGE_REGISTRY/$IMAGE_REPOSITORY/rag-system-backend:$BACKEND_IMAGE_TAG"

# Frontend image build
log "Frontend Docker image build ediliyor..."
cd ../frontend
docker build -t $IMAGE_REGISTRY/$IMAGE_REPOSITORY/rag-system-frontend:$FRONTEND_IMAGE_TAG .
log "✅ Frontend image build edildi: $IMAGE_REGISTRY/$IMAGE_REPOSITORY/rag-system-frontend:$FRONTEND_IMAGE_TAG"

cd ../..

# Image'ları push et
log "Image'lar GitHub Container Registry'ye push ediliyor..."
docker push $IMAGE_REGISTRY/$IMAGE_REPOSITORY/rag-system-backend:$BACKEND_IMAGE_TAG
docker push $IMAGE_REGISTRY/$IMAGE_REPOSITORY/rag-system-frontend:$FRONTEND_IMAGE_TAG

log "🎉 Tüm image'lar başarıyla build edildi ve push edildi!"
log ""
log "📋 Build edilen image'lar:"
log "  Backend:  $IMAGE_REGISTRY/$IMAGE_REPOSITORY/rag-system-backend:$BACKEND_IMAGE_TAG"
log "  Frontend: $IMAGE_REGISTRY/$IMAGE_REPOSITORY/rag-system-frontend:$FRONTEND_IMAGE_TAG"
log ""
log "💡 Şimdi 'make up' komutunu çalıştırabilirsiniz"
