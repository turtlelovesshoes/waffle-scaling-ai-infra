#!/usr/bin/env bash
set -euo pipefail

# Accept app name as first argument, default to "mkdocs"
APP_NAME="${1:-portfolio}"
IMAGE_NAME="$APP_NAME"
CONTAINER_NAME="${APP_NAME}-test"
TEST_PROJECT="${APP_NAME}"

echo "============================="
echo "${TEST_PROJECT} Docker Test Runner"
echo "============================="

# Detect OS and architecture
OS_TYPE=$(uname | tr '[:upper:]' '[:lower:]')
ARCH_TYPE=$(uname -m)
echo "[INFO] Detected OS: $OS_TYPE"
echo "[INFO] Detected Architecture: $ARCH_TYPE"

# Determine Docker build command
BUILD_CMD="docker build -t $IMAGE_NAME ."
if [[ "$OS_TYPE" == "msys"* || "$OS_TYPE" == "cygwin"* || "$OS_TYPE" == "mingw"* ]]; then
    echo "[INFO] Windows detected → using Buildx with linux/amd64"
    BUILD_CMD="docker buildx build --platform linux/amd64 --load -t $IMAGE_NAME ."
    PROJECT_ROOT="$(pwd -W)"  # convert Git Bash path to Windows style
    echo "$PROJECT_ROOT"
else
    PROJECT_ROOT="$(pwd)"
    echo "$PROJECT_ROOT"
fi

# Step 1: Build image
echo "-----------------------------"
echo "🚀 Step 1: Building image"
echo "Running command: $BUILD_CMD"
eval $BUILD_CMD
echo "[SUCCESS] Image '$IMAGE_NAME' built."

# Step 2: Prepare test project
echo "-----------------------------"
echo "🛠 Step 2: Preparing test project in '$APP_NAME/'"
PROJECT_PATH="$PROJECT_ROOT/$APP_NAME"
if [ ! -d "$PROJECT_PATH" ]; then
    echo "[ERROR] Project directory '$PROJECT_PATH' does not exist."
    exit 1
fi
echo "[SUCCESS] Project directory '$PROJECT_PATH' found."

# Step 3: Run container interactively (keeps container alive)
echo "-----------------------------"
echo "▶️ Step 3: Running container '$CONTAINER_NAME'"
docker run --rm -it \
    --name $CONTAINER_NAME \
    -v "${PROJECT_PATH}:/docs" \
    -p 8000:8000 \
    $IMAGE_NAME serve -a 0.0.0.0:8000

echo "============================="
echo " 🎉 ${APP_NAME}'s container exited. Workflow finished."
echo "============================="
