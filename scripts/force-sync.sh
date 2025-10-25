#!/bin/bash

# ArgoCD Force Sync Script
# Bu script ArgoCD uygulamasını force sync yapar

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
    error ".env dosyası bulunamadı"
fi

log "ArgoCD Force Sync başlatılıyor..."

# ArgoCD uygulamasını force sync yap
log "ArgoCD uygulaması force sync ediliyor..."
argocd app sync ubuntu-rag-sistemi --force

log "✅ ArgoCD force sync tamamlandı!"
log "ArgoCD arayüzünde senkronizasyonu izleyebilirsiniz: make ui-argo"
