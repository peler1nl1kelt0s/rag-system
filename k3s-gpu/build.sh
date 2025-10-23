#!/bin/bash

set -euxo pipefail

K3S_TAG=${K3S_TAG:="v1.31.5-k3s1"}
CUDA_TAG=${CUDA_TAG:="12.4.1-base-ubuntu22.04"}
IMAGE_REGISTRY=${IMAGE_REGISTRY:="ghcr.io"}
IMAGE_REPOSITORY=${IMAGE_REPOSITORY:="peler1nl1kelt0s/k3s-gpu"}
IMAGE_TAG="$K3S_TAG-cuda"
IMAGE=${IMAGE:="$IMAGE_REGISTRY/$IMAGE_REPOSITORY:$IMAGE_TAG"}

echo "Building custom K3s image with GPU support..."
echo "IMAGE=$IMAGE"

docker build \
  --build-arg K3S_TAG=$K3S_TAG \
  --build-arg CUDA_TAG=$CUDA_TAG \
  -t $IMAGE .

echo ""
echo "✅ Image built successfully: $IMAGE"
echo ""
echo "To push to registry, run:"
echo "  docker push $IMAGE"
echo ""
echo "To use with k3d, run:"
echo "  k3d cluster create rag-cluster --image=$IMAGE --gpus=1"

