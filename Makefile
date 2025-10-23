# === Değişkenler ===
# Buradaki değişkenleri projenize göre özelleştirebilirsiniz.
CLUSTER_NAME       ?= rag-cluster
ARGOCD_NS          ?= argocd
APP_NS             ?= rag-system
NVIDIA_NS          ?= nvidia-device-plugin

# Custom K3s image with GPU support
# GitHub Actions otomatik olarak bu image'ı build edip push edecek
K3S_GPU_IMAGE      ?= ghcr.io/peler1nl1kelt0s/k3s-gpu:v1.31.5-k3s1-cuda
USE_CUSTOM_IMAGE   ?= false

# Git bilgilerini otomatik al
# Not: GitHub repo'nuz private ise, ArgoCD'nin erişimi için ek ayar gerekebilir.
# Bu kurulum, public repo veya ArgoCD'nin aynı kümede olduğu varsayımıyla çalışır.
GITHUB_USER        ?= $(shell git config user.name)
GITHUB_REPO        ?= $(shell basename `git rev-parse --show-toplevel`)

# === Makefile Kuralları ===
.PHONY: all up down destroy clean cluster install-gpu-plugin check-gpu install-argocd deploy-app ui-argo ui-app ingest status build-gpu-image help

# Varsayılan komut (sadece 'make' yazarsanız)
all: help

# Ana 'up' komutu. Her şeyi sırayla kurar.
up: cluster install-gpu-plugin check-gpu install-argocd deploy-app
	@echo "\n🎉 Kurulum Tamamlandı! 🎉"
	@echo "Şimdi ArgoCD arayüzünü kontrol edin:"
	@echo "  make ui-argo"
	@echo "Veya direkt uygulama arayüzüne gidin (Senkronizasyon bittikten sonra):"
	@echo "  make ui-app"

# Küme ve tüm uygulamaları yok et
destroy:
	@echo "🔥 Tüm k3d kümesi '$(CLUSTER_NAME)' siliniyor..."
	@k3d cluster delete $(CLUSTER_NAME) || true

# Sadece Kubernetes uygulamalarını sil (küme kalsın)
clean:
	@echo "🧹 Kubernetes uygulamaları siliniyor..."
	@kubectl delete -f manifests/06-argocd-app.yaml || true
	@kubectl delete namespace $(APP_NS) || true
	@kubectl delete namespace $(ARGOCD_NS) || true
	@kubectl delete namespace $(NVIDIA_NS) || true

# --- GPU Image Build ---

# Custom K3s GPU image build et (GitHub Actions ile otomatik)
build-gpu-image:
	@echo "🔨 Custom K3s GPU image GitHub Actions ile build ediliyor..."
	@echo "⚠️  Not: Bu komut sadece k3s-gpu/ dizinindeki değişiklikleri commit eder."
	@echo "   Gerçek build GitHub Actions'da yapılır (5-10 dakika sürer)."
	@echo ""
	@echo "📋 Adımlar:"
	@echo "  1. k3s-gpu/ dizinindeki değişiklikleri commit et"
	@echo "  2. GitHub Actions otomatik build edecek"
	@echo "  3. Build tamamlandıktan sonra: USE_CUSTOM_IMAGE=true make up"
	@echo ""
	@echo "💡 Manuel build için: cd k3s-gpu && ./build.sh"

# --- Kurulum Adımları ---

# Adım 1: GPU destekli k3d kümesini oluştur
cluster:
	@echo "🚀 k3d kümesi '$(CLUSTER_NAME)' GPU desteği ile oluşturuluyor..."
ifeq ($(USE_CUSTOM_IMAGE),true)
	@echo "✅ Custom K3s GPU image kullanılıyor: $(K3S_GPU_IMAGE)"
	@echo "⚠️  Not: Bu image NVIDIA Container Toolkit ve device plugin içerir."
	@k3d cluster create $(CLUSTER_NAME) \
	  --image $(K3S_GPU_IMAGE) \
	  --gpus all \
	  --k3s-arg "--disable=traefik@server:0"
else
	@echo "⚠️  Standard K3s image kullanılıyor (GPU CPU modunda çalışacak)"
	@echo "💡 GPU desteği için: make build-gpu-image && USE_CUSTOM_IMAGE=true make cluster"
	@k3d cluster create $(CLUSTER_NAME) \
	  --gpus all \
	  --image rancher/k3s:v1.31.5-k3s1 \
	  --k3s-arg "--disable=traefik@server:0"
endif
	@echo "⏳ Kubernetes API sunucusunun hazır olması bekleniyor..."
	@sleep 10
	@kubectl wait --for=condition=ready node --all --timeout=120s

# Adım 2: GPU yapılandırması
install-gpu-plugin:
	@echo "🔌 GPU yapılandırması kontrol ediliyor..."
ifeq ($(USE_CUSTOM_IMAGE),true)
	@echo "✅ Custom K3s image kullanıldı - NVIDIA device plugin otomatik deploy edildi"
	@echo "⏳ Device plugin DaemonSet'inin hazır olması bekleniyor..."
	@sleep 5
	@kubectl wait --for=condition=ready pod -l name=nvidia-device-plugin-ds -n kube-system --timeout=60s || echo "⚠️  Device plugin beklemede, devam ediliyor..."
else
	@echo "⚠️  Standard image kullanıldı - GPU CPU modunda çalışacak"
	@echo "💡 Tam GPU desteği için custom image gerekli"
endif
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
	@echo "\n\n🚀 ArgoCD Arayüzü: https://localhost:8080 (Ctrl+C ile durdurun)"
	@kubectl port-forward svc/argocd-server -n $(ARGOCD_NS) --address 0.0.0.0 8080:443

# Streamlit (Frontend) arayüzünü port-forward et
ui-app:
	@echo "🚀 Streamlit Arayüzü: http://localhost:8501 (Ctrl+C ile durdurun)"
	@kubectl port-forward svc/rag-frontend-service -n $(APP_NS) --address 0.0.0.0 8501:8501

# Veri yükleme (ingest) endpoint'ini bir kez tetikle
ingest:
	@echo "⏳ Backend port-forward başlatılıyor..."
	@kubectl port-forward svc/rag-backend-service -n $(APP_NS) --address 0.0.0.0 8000:8000 & \
	# port-forward işleminin PID'sini (proses ID) al
	KUBE_PID=$$! ; \
	echo "Port-forward PID: $$KUBE_PID" ; \
	echo "Veri yükleme (Ingest) tetikleniyor... (Bu işlem uzun sürebilir)" ; \
	sleep 3 ; \
	curl -X POST http://localhost:8000/ingest ; \
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
	@echo "Lokal RAG Sistemi Makefile"
	@echo "====================================="
	@echo ""
	@echo "🚀 Temel Komutlar:"
	@echo "  make up                    : Tüm sistemi kurar (Cluster, GPU, ArgoCD, App)"
	@echo "  make destroy               : k3d kümesini tamamen siler"
	@echo "  make clean                 : Sadece uygulamaları siler (küme kalır)"
	@echo "  make status                : Tüm pod'ların durumunu gösterir"
	@echo ""
	@echo "🎮 Arayüzler:"
	@echo "  make ui-argo               : ArgoCD arayüzü (https://localhost:8080)"
	@echo "  make ui-app                : Streamlit frontend (http://localhost:8501)"
	@echo ""
	@echo "📊 Veri İşlemleri:"
	@echo "  make ingest                : PDF'leri Qdrant'a yükler"
	@echo ""
	@echo "🎯 GPU Desteği (Gelişmiş):"
	@echo "  make build-gpu-image       : Custom K3s GPU image build et"
	@echo "  USE_CUSTOM_IMAGE=true make up : GPU image ile cluster kur"
	@echo ""
	@echo "💡 İpucu: CPU modunda test için direkt 'make up' yeterli"
	@echo "   Tam GPU desteği için: make build-gpu-image sonra USE_CUSTOM_IMAGE=true make up"