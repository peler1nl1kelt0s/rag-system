# Custom K3s Image with GPU Support

Bu dizin, NVIDIA GPU desteği olan custom K3s image'ı için gerekli dosyaları içerir.

## 📋 İçerik

- `Dockerfile`: CUDA ve NVIDIA Container Toolkit ile K3s image'ı
- `device-plugin-daemonset.yaml`: NVIDIA device plugin (otomatik deploy için)
- `build.sh`: Build script

## 🚀 Kullanım

### 1. Image'ı Build Et

```bash
cd k3s-gpu
chmod +x build.sh
./build.sh
```

### 2. (Opsiyonel) Registry'ye Push Et

```bash
# GitHub Container Registry'ye login
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Push
docker push ghcr.io/peler1nl1kelt0s/k3s-gpu:v1.31.5-k3s1-cuda
```

### 3. k3d Cluster'ı Custom Image ile Oluştur

```bash
k3d cluster create rag-cluster \
  --image=ghcr.io/peler1nl1kelt0s/k3s-gpu:v1.31.5-k3s1-cuda \
  --gpus=1 \
  --k3s-arg "--disable=traefik@server:0"
```

## 📝 Not

- Ollama manifest'inde `runtimeClassName: nvidia` eklenmelidir
- GPU gerektiren tüm pod'lara bu RuntimeClass eklenmelidir
- NVIDIA device plugin otomatik olarak deploy edilir

## 🔍 Test

```bash
# GPU'nun görünüp görünmediğini kontrol et
kubectl describe nodes | grep nvidia.com/gpu

# Örnek GPU pod'u:
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia"}}' \
  -- nvidia-smi
```

