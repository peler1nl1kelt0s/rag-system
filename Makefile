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

# Cluster içindeki tüm uygulamaları yok et (K3s kalır)
down:
	@echo "🔥 Cluster içindeki tüm uygulamalar siliniyor..."
	@kubectl delete -f manifests/06-argocd-app.yaml || true
	@kubectl delete namespace $(APP_NS) || true
	@kubectl delete namespace $(ARGOCD_NS) || true
	@kubectl delete -f k3s-gpu/device-plugin-daemonset.yaml || true
	@echo "✅ Cluster temizlendi! K3s çalışmaya devam ediyor."

# --- Kurulum Adımları ---

# K3s kurulumu
install-k3s:
	@echo "🚀 K3s kurulumu kontrol ediliyor..."
	@if command -v k3s > /dev/null 2>&1; then \
		echo "✅ K3s zaten kurulu"; \
		if ! sudo systemctl is-active --quiet k3s; then \
			echo "⚠️  K3s servisi durmuş, başlatılıyor..."; \
			sudo systemctl start k3s; \
			sleep 5; \
		fi; \
	else \
		echo "📦 K3s kuruluyor..."; \
		curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -; \
		sleep 10; \
		sudo systemctl enable k3s; \
		sudo systemctl start k3s; \
	fi

# K3s konfigürasyonu
configure-k3s:
	@echo "🔧 K3s konfigürasyonu yapılıyor..."
	@if [ ! -f ~/.kube/config ]; then \
		mkdir -p ~/.kube; \
		sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config; \
		sudo chown $(shell whoami):$(shell whoami) ~/.kube/config; \
	fi

# GPU plugin kurulumu
install-gpu-plugin:
	@echo "🔌 NVIDIA GPU plugin kuruluyor..."
	@which nvidia-ctk > /dev/null 2>&1 || (echo "❌ NVIDIA Container Toolkit bulunamadı." && exit 1)
	@sudo nvidia-ctk runtime configure --runtime=containerd
	@sudo systemctl restart containerd
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
	@kubectl port-forward svc/rag-frontend -n $(APP_NS) $(FRONTEND_PORT):8501

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
	@echo "  make down            : Tüm uygulamaları siler (K3s kalır)"
	@echo "  make ui-argo         : ArgoCD arayüzünü açar"
	@echo "  make ui-app          : Streamlit arayüzünü açar"
	@echo "  make status          : Pod durumlarını gösterir"
	@echo ""
	@echo "📋 Notlar:"
	@echo "  - PDF'ler apps/backend/apache_pdfs/ klasörüne koyulur"
	@echo "  - Sistem otomatik olarak PDF'leri vector database'ye yükler"
	@echo "  - ArgoCD şifresi: make ui-argo komutunda gösterilir"