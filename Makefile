# === Environment Variables ===
# Load environment variables from .env file
ifneq (,$(wildcard .env))
    include .env
    export
endif

# === Default Variables ===
# Buradaki değişkenleri projenize göre özelleştirebilirsiniz.
CLUSTER_NAME       ?= rag-cluster
ARGOCD_NS          ?= argocd
APP_NS             ?= rag-system
NVIDIA_NS          ?= nvidia-device-plugin

# GPU Configuration
USE_CUSTOM_IMAGE   ?= true

# Git bilgilerini otomatik al
GITHUB_USER        ?= $(shell git config user.name)
GITHUB_REPO        ?= $(shell basename `git rev-parse --show-toplevel`)

# === Makefile Kuralları ===
.PHONY: all up down destroy clean cluster install-gpu-plugin check-gpu install-argocd deploy-app ui-argo ui-app ingest status build-images setup-ubuntu install-k3s configure-k3s help

# Varsayılan komut (sadece 'make' yazarsanız)
all: help

# Ana 'up' komutu. Her şeyi sırayla kurar.
up: build-images cluster install-gpu-plugin check-gpu install-argocd deploy-app
	@echo "\n🎉 Kurulum Tamamlandı! 🎉"
	@echo "Şimdi ArgoCD arayüzünü kontrol edin:"
	@echo "  make ui-argo"
	@echo "Veya direkt uygulama arayüzüne gidin (Senkronizasyon bittikten sonra):"
	@echo "  make ui-app"

# K3s ve tüm uygulamaları yok et
destroy:
	@echo "🔥 K3s ve tüm uygulamalar siliniyor..."
	@kubectl delete -f manifests/06-argocd-app.yaml || true
	@kubectl delete namespace $(APP_NS) || true
	@kubectl delete namespace $(ARGOCD_NS) || true
	@kubectl delete -f k3s-gpu/device-plugin-daemonset.yaml || true
	@echo "🛑 K3s servisi durduruluyor..."
	@sudo systemctl stop k3s || true
	@sudo systemctl disable k3s || true
	@echo "🗑️  K3s kaldırılıyor..."
	@sudo /usr/local/bin/k3s-uninstall.sh || true
	@echo "✅ K3s tamamen kaldırıldı!"

# Sadece Kubernetes uygulamalarını sil (K3s kalsın)
clean:
	@echo "🧹 Kubernetes uygulamaları siliniyor..."
	@kubectl delete -f manifests/06-argocd-app.yaml || true
	@kubectl delete namespace $(APP_NS) || true
	@kubectl delete namespace $(ARGOCD_NS) || true
	@kubectl delete -f k3s-gpu/device-plugin-daemonset.yaml || true

# --- Image Build ---

# Backend ve Frontend image'larını build et
build-images:
	@echo "🔨 Backend ve Frontend image'ları build ediliyor..."
	@./scripts/build-images.sh


# --- Kurulum Adımları ---

# Ubuntu sistem kurulumu
setup-ubuntu:
	@echo "🚀 Ubuntu sistem kurulumu başlıyor..."
	@./scripts/ubuntu-setup.sh

# Adım 1: K3s kurulumu (Ubuntu için)
install-k3s:
	@echo "🚀 K3s kurulumu kontrol ediliyor..."
	@if command -v k3s > /dev/null 2>&1; then \
		echo "✅ K3s zaten kurulu"; \
	else \
		echo "📦 K3s kuruluyor..."; \
		curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -; \
		echo "⏳ K3s servisinin başlaması bekleniyor..."; \
		sleep 10; \
		sudo systemctl enable k3s; \
		sudo systemctl start k3s; \
		echo "✅ K3s başarıyla kuruldu!"; \
	fi

# Adım 2: K3s konfigürasyonu
configure-k3s:
	@echo "🔧 K3s konfigürasyonu yapılıyor..."
	@if [ ! -f ~/.kube/config ]; then \
		sudo mkdir -p /etc/rancher/k3s; \
		sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config; \
		sudo chown $(shell whoami):$(shell whoami) ~/.kube/config; \
		echo "✅ K3s konfigürasyonu tamamlandı!"; \
	else \
		echo "✅ kubectl konfigürasyonu zaten mevcut"; \
	fi

# Adım 3: GPU plugin kurulumu
cluster: install-k3s configure-k3s
	@echo "🎯 K3s cluster hazır!"

# Adım 4: GPU yapılandırması
install-gpu-plugin:
	@echo "🔌 NVIDIA GPU plugin kuruluyor..."
	@echo "📦 NVIDIA Container Toolkit kurulumu kontrol ediliyor..."
	@which nvidia-ctk > /dev/null 2>&1 || (echo "❌ NVIDIA Container Toolkit bulunamadı. Lütfen önce kurun." && exit 1)
	@echo "✅ NVIDIA Container Toolkit mevcut"
	@echo "🔧 containerd runtime konfigürasyonu yapılıyor..."
	@sudo nvidia-ctk runtime configure --runtime=containerd
	@sudo systemctl restart containerd
	@echo "📋 NVIDIA device plugin DaemonSet kuruluyor..."
	@kubectl apply -f k3s-gpu/device-plugin-daemonset.yaml
	@echo "⏳ Device plugin DaemonSet'inin hazır olması bekleniyor..."
	@sleep 10
	@kubectl wait --for=condition=ready pod -l name=nvidia-device-plugin-ds -n kube-system --timeout=120s || echo "⚠️  Device plugin beklemede, devam ediliyor..."
	@echo "✅ GPU yapılandırması tamamlandı"

# Adım 3: GPU'nun host'ta erişilebilir olduğunu doğrula
check-gpu:
	@echo "🔎 Host sisteminde GPU'nun varlığı kontrol ediliyor..."
	@nvidia-smi > /dev/null 2>&1 && echo "✅ nvidia-smi çalışıyor - GPU erişilebilir!" || \
	  (echo "⚠️  nvidia-smi çalışmıyor. GPU olmadan devam ediliyor (CPU modunda çalışacak)." && true)

# Adım 4: ArgoCD'yi kur
install-argocd:
	@echo "🔄 ArgoCD kuruluyor..."
	@kubectl create namespace $(ARGOCD_NS) || true
	@kubectl apply -n $(ARGOCD_NS) -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	@echo "⏳ ArgoCD sunucusunun başlaması bekleniyor..."
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n $(ARGOCD_NS) --timeout=300s

# Adım 5: Ana RAG uygulamasını ArgoCD'ye deploy et
deploy-app:
	@echo "🚀 RAG Uygulaması ArgoCD'ye bildiriliyor..."
	@echo "Manifestlerinizin şu repoyu hedeflediğinden emin olun: $(GITHUB_USER)/$(GITHUB_REPO)"
	# ÖNEMLİ: '06-argocd-app.yaml' dosyanızın içindeki repoURL'in doğru olduğundan emin olun!
	@kubectl apply -f manifests/06-argocd-app.yaml
	@echo "✅ ArgoCD uygulaması oluşturuldu. 'make ui-argo' ile senkronizasyonu izleyin."

# --- Yardımcı Komutlar ---

# ArgoCD arayüzünü port-forward et ve şifreyi göster
ui-argo:
	@echo "🔑 ArgoCD admin şifresi:"
	@kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d ; echo
	@echo "\n\n🚀 ArgoCD Arayüzü: https://localhost:$(ARGOCD_PORT) (Ctrl+C ile durdurun)"
	@kubectl port-forward svc/argocd-server -n $(ARGOCD_NS) --address 0.0.0.0 $(ARGOCD_PORT):443

# Streamlit (Frontend) arayüzünü port-forward et
ui-app:
	@echo "🚀 Streamlit Arayüzü: http://localhost:$(FRONTEND_PORT) (Ctrl+C ile durdurun)"
	@kubectl port-forward svc/rag-frontend-service -n $(APP_NS) --address 0.0.0.0 $(FRONTEND_PORT):8501

# Veri yükleme (ingest) endpoint'ini bir kez tetikle
ingest:
	@echo "⏳ Backend port-forward başlatılıyor..."
	@kubectl port-forward svc/rag-backend-service -n $(APP_NS) --address 0.0.0.0 $(BACKEND_PORT):8000 & \
	# port-forward işleminin PID'sini (proses ID) al
	KUBE_PID=$$! ; \
	echo "Port-forward PID: $$KUBE_PID" ; \
	echo "Veri yükleme (Ingest) tetikleniyor... (Bu işlem uzun sürebilir)" ; \
	sleep 3 ; \
	curl -X POST http://localhost:$(BACKEND_PORT)/ingest ; \
	echo "\n✅ Ingest isteği gönderildi." ; \
	echo "Port-forward kapatılıyor..." ; \
	kill $$KUBE_PID

# Tüm podların durumunu göster
status:
	@echo "--- ArgoCD Podları ($(ARGOCD_NS)) ---"
	@kubectl get pods -n $(ARGOCD_NS)
	@echo "\n--- NVIDIA Plugin Podları ($(NVIDIA_NS)) ---"
	@kubectl get pods -n $(NVIDIA_NS)
	@echo "\n--- RAG Uygulama Podları ($(APP_NS)) ---"
	@kubectl get pods -n $(APP_NS)

# Yardım menüsü
help:
	@echo "Ubuntu RAG Sistemi Makefile (K3s)"
	@echo "====================================="
	@echo ""
	@echo "🚀 Temel Komutlar:"
	@echo "  make up                    : Tüm sistemi kurar (K3s, GPU, ArgoCD, App)"
	@echo "  make destroy               : K3s'i tamamen siler"
	@echo "  make clean                 : Sadece uygulamaları siler (K3s kalır)"
	@echo "  make status                : Tüm pod'ların durumunu gösterir"
	@echo ""
	@echo "🎮 Arayüzler:"
	@echo "  make ui-argo               : ArgoCD arayüzü (https://localhost:$(ARGOCD_PORT))"
	@echo "  make ui-app                : Streamlit frontend (http://localhost:$(FRONTEND_PORT))"
	@echo ""
	@echo "📊 Veri İşlemleri:"
	@echo "  make ingest                : PDF'leri Qdrant'a yükler"
	@echo ""
	@echo "🔧 Kurulum Adımları:"
	@echo "  make setup-ubuntu          : Ubuntu sistem kurulumu (ilk kez)"
	@echo "  make install-k3s           : K3s'i Ubuntu'ya kurar"
	@echo "  make configure-k3s         : K3s konfigürasyonunu yapar"
	@echo "  make install-gpu-plugin    : NVIDIA GPU plugin kurar"
	@echo "  make check-gpu             : GPU erişilebilirliğini kontrol eder"
	@echo ""
	@echo "🏗️  Build Komutları:"
	@echo "  make build-images          : Backend ve Frontend image'larını build eder"
	@echo ""
	@echo "💡 İpucu: .env dosyasını düzenleyerek konfigürasyonu özelleştirin"
	@echo "   GPU desteği için NVIDIA Container Toolkit kurulu olmalı"