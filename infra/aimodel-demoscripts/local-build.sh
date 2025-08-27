#!/bin/bash

set -euo pipefail
## Local build and test app on Docker Desktop and Minikube

IMAGE_NAME="aidemo-speechify"
CONTAINER_NAME="aidemo-speechify"
APP_PATH="../../k8s/aidemo-app"

echo "============================="
echo " aidemo-speechify Docker Test Runner"
echo "============================="

# Detect OS and architecture
OS_TYPE=$(uname | tr '[:upper:]' '[:lower:]')
ARCH_TYPE=$(uname -m)
echo "[INFO] Detected OS: $OS_TYPE"
echo "[INFO] Detected Architecture: $ARCH_TYPE"

# Determine Docker build command
BUILD_CMD="docker build -t $IMAGE_NAME $APP_PATH"
if [[ "$OS_TYPE" == "msys"* || "$OS_TYPE" == "cygwin"* || "$OS_TYPE" == "mingw"* ]]; then
    echo "[INFO] Windows detected → using Buildx with linux/amd64"
    BUILD_CMD="docker buildx build --platform linux/amd64 --load -t $IMAGE_NAME $APP_PATH"
fi

# Step 1: Build image
echo "-----------------------------"
echo "🚀 Step 1: Building image from '$APP_PATH'"
echo "Running command: $BUILD_CMD"
eval $BUILD_CMD
echo "[SUCCESS] Image '$IMAGE_NAME' built."

# Step 2: Run container interactively
echo "-----------------------------"
echo "▶️ Step 2: Running container '$CONTAINER_NAME'"
docker run --rm -it \
    --name $CONTAINER_NAME \
    -p 5000:5000 \
    -e SPEECHIFY_API_KEY="${SPEECHIFY_API_KEY:-sk_live_XXXXXXXXXXXXXXXX}" \
    $IMAGE_NAME

echo "============================="
echo " 🎉 Container exited. Workflow finished."
echo "============================="

