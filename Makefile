# Ubuntu RAG Sistemi Makefile (K3s)
# ==================================

# .env dosyasını yükle
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Namespace'ler
APP_NS        ?= rag-system
ARGOCD_NS     ?= argocd
NVIDIA_NS     ?= kube-system

# Port'lar
ARGOCD_PORT   ?= 8080
FRONTEND_PORT ?= 8501

# Git bilgilerini otomatik al
GITHUB_USER   ?= $(shell git config user.name)
GITHUB_REPO   ?= $(shell basename `git rev-parse --show-toplevel`)

# === Makefile Kuralları ===
.PHONY: all up down ui-argo ui-app status help

# Varsayılan komut (sadece 'make' yazarsanız)
all: help

# Ana 'up' komutu. Her şeyi sırayla kurar.
up: install-k3s configure-k3s install-gpu-plugin install-argocd create-secrets deploy-app
	@echo "\n🎉 Kurulum Tamamlandı! 🎉"
	@echo "ArgoCD arayüzü: make ui-argo"
	@echo "Streamlit arayüzü: make ui-app"

# Tüm sistemi yok et (K3s dahil)
down:
	@echo "🔥 Tüm sistem siliniyor (K3s dahil)..."
	@kubectl delete -f manifests/06-argocd-app.yaml || true
	@kubectl delete namespace $(APP_NS) || true
	@kubectl delete namespace $(ARGOCD_NS) || true
	@kubectl delete -f k3s-gpu/device-plugin-daemonset.yaml || true
	@echo "🛑 K3s servisi durduruluyor..."
	@sudo systemctl stop k3s || true
	@echo "🗑️  K3s kaldırılıyor..."
	@sudo /usr/local/bin/k3s-uninstall.sh || true
	@echo "✅ Tüm sistem tamamen silindi!"

# --- Kurulum Adımları ---

# K3s kurulumu
install-k3s:
	@echo "🚀 K3s kurulumu kontrol ediliyor..."
	@if command -v k3s > /dev/null 2>&1; then \
		echo "✅ K3s binary mevcut"; \
		if ! sudo systemctl is-active --quiet k3s; then \
			echo "⚠️  K3s servisi durmuş, başlatılıyor..."; \
			sudo systemctl start k3s; \
			echo "⏳ Servisin başlaması bekleniyor (30 saniye)..."; \
			sleep 30; \
		else \
			echo "✅ K3s servisi çalışıyor"; \
		fi; \
	else \
		echo "📦 K3s kuruluyor..."; \
		curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -; \
		echo "⏳ K3s servisinin başlaması bekleniyor (60 saniye)..."; \
		sleep 60; \
		if ! sudo systemctl is-active --quiet k3s; then \
			echo "❌ K3s servisi başlatılamadı!"; \
			echo "🔍 Hata detayları:"; \
			sudo journalctl -u k3s -n 50 --no-pager; \
			exit 1; \
		fi; \
		echo "✅ K3s servisi başarıyla başlatıldı"; \
	fi

# K3s konfigürasyonu
configure-k3s:
	@echo "🔧 K3s konfigürasyonu yapılıyor..."
	@echo "⏳ K3s config dosyasının oluşmasını bekleniyor..."
	@COUNTER=0; \
	until [ -f /etc/rancher/k3s/k3s.yaml ] || [ $$COUNTER -eq 12 ]; do \
		echo "⏳ Config dosyası henüz yok, bekleniyor... ($$((COUNTER*5)) saniye)"; \
		sleep 5; \
		COUNTER=$$((COUNTER+1)); \
	done; \
	if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then \
		echo "❌ K3s config dosyası oluşmadı!"; \
		echo "🔍 K3s servisi düzgün çalışmıyor olabilir"; \
		sudo systemctl status k3s --no-pager; \
		exit 1; \
	fi
	@echo "✅ Config dosyası bulundu"
	@mkdir -p ~/.kube
	@sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
	@sudo chown $(shell whoami):$(shell whoami) ~/.kube/config
	@echo "✅ Kubeconfig kopyalandı"
	@echo "⏳ K3s API'nin hazır olması bekleniyor (max 3 dakika)..."
	@COUNTER=0; \
	until kubectl get nodes > /dev/null 2>&1 || [ $$COUNTER -eq 36 ]; do \
		echo "⏳ K3s API henüz hazır değil, bekleniyor... ($$((COUNTER*5)) saniye)"; \
		sleep 5; \
		COUNTER=$$((COUNTER+1)); \
	done; \
	if [ $$COUNTER -eq 36 ]; then \
		echo "❌ K3s API 3 dakika içinde hazır olmadı!"; \
		echo "🔍 K3s servisi durumu:"; \
		sudo systemctl status k3s --no-pager; \
		echo ""; \
		echo "🔍 Son loglar:"; \
		sudo journalctl -u k3s -n 30 --no-pager; \
		exit 1; \
	fi
	@echo "✅ K3s hazır!"
	@kubectl get nodes

# GPU plugin kurulumu
install-gpu-plugin:
	@echo "🔌 NVIDIA GPU plugin kuruluyor..."
	@which nvidia-ctk > /dev/null 2>&1 || (echo "❌ NVIDIA Container Toolkit bulunamadı." && exit 1)
	@sudo nvidia-ctk runtime configure --runtime=containerd
	@sudo systemctl restart containerd
	@sleep 5
	@kubectl apply -f k3s-gpu/device-plugin-daemonset.yaml --validate=false
	@sleep 10

# ArgoCD kurulumu
install-argocd:
	@echo "🔄 ArgoCD kuruluyor..."
	@kubectl create namespace $(ARGOCD_NS) || true
	@kubectl apply -n $(ARGOCD_NS) -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n $(ARGOCD_NS) --timeout=300s

# Tüm secret'ları oluştur
create-secrets:
	@echo "🔐 Secret'lar oluşturuluyor..."
	@if [ -z "$(GITHUB_TOKEN)" ] || [ "$(GITHUB_TOKEN)" = "your_github_token_here" ]; then \
		echo "❌ GITHUB_TOKEN .env dosyasında tanımlanmamış!"; \
		exit 1; \
	fi
	@kubectl create namespace $(APP_NS) || true
	@kubectl create secret generic github-repo-secret \
		--from-literal=type=git \
		--from-literal=url=https://github.com/$(GITHUB_USER)/$(GITHUB_REPO).git \
		--from-literal=username=$(GITHUB_USER) \
		--from-literal=password=$(GITHUB_TOKEN) \
		-n argocd \
		--dry-run=client -o yaml | \
		kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | \
		kubectl apply -f -
	@kubectl create secret docker-registry ghcr-secret \
		--docker-server=ghcr.io \
		--docker-username=$(GITHUB_USER) \
		--docker-password=$(GITHUB_TOKEN) \
		--docker-email=$(GITHUB_USER)@users.noreply.github.com \
		-n $(APP_NS) \
		--dry-run=client -o yaml | kubectl apply -f -

# RAG uygulamasını deploy et
deploy-app:
	@echo "🚀 RAG Uygulaması deploy ediliyor..."
	@kubectl apply -f manifests/06-argocd-app.yaml

# --- Yardımcı Komutlar ---

# ArgoCD arayüzünü port-forward et
ui-argo:
	@echo "🌐 ArgoCD arayüzü: http://localhost:$(ARGOCD_PORT)"
	@echo "Şifre: $$(kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
	@kubectl port-forward svc/argocd-server -n $(ARGOCD_NS) $(ARGOCD_PORT):443

# Streamlit arayüzünü port-forward et
ui-app:
	@echo "🌐 Streamlit arayüzü: http://localhost:$(FRONTEND_PORT)"
	@kubectl port-forward svc/rag-frontend-service -n $(APP_NS) $(FRONTEND_PORT):8501

# Cluster durumunu kontrol et
status:
	@echo "📊 Cluster Durumu:"
	@kubectl get nodes
	@echo ""
	@kubectl get pods -n $(APP_NS) 2>/dev/null || echo "rag-system namespace'i bulunamadı"
	@kubectl get pods -n $(ARGOCD_NS) 2>/dev/null || echo "argocd namespace'i bulunamadı"

# Yardım menüsü
help:
	@echo "Ubuntu RAG Sistemi Makefile (K3s)"
	@echo "=================================="
	@echo ""
	@echo "🚀 Ana Komutlar:"
	@echo "  make up              : Tüm sistemi kurar (K3s + GPU + ArgoCD + RAG)"
	@echo "  make down            : Tüm sistemi siler (K3s dahil)"
	@echo "  make ui-argo         : ArgoCD arayüzünü açar"
	@echo "  make ui-app          : Streamlit arayüzünü açar"
	@echo "  make status          : Pod durumlarını gösterir"
	@echo ""
	@echo "📋 Notlar:"
	@echo "  - PDF'ler apps/backend/apache_pdfs/ klasörüne koyulur"
	@echo "  - Sistem otomatik olarak PDF'leri vector database'ye yükler"
	@echo "  - ArgoCD şifresi: make ui-argo komutunda gösterilir"