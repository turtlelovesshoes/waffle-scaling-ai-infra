#!/usr/bin/env bash
set -euo pipefail

# Accept app name as first argument, default to "mkdocs"
APP_NAME="${1:-portfolio}"
IMAGE_NAME="$APP_NAME"
CONTAINER_NAME="${APP_NAME}"
TEST_PROJECT="${APP_NAME}"

echo "============================="
echo "${TEST_PROJECT} Docker Test Runner"
echo "============================="

# Detect OS and architecture
OS_TYPE=$(uname | tr '[:upper:]' '[:lower:]')
ARCH_TYPE=$(uname -m)
echo "[INFO] Detected OS: $OS_TYPE"
echo "[INFO] Detected Architecture: $ARCH_TYPE"

# Determine project root
if [[ "$OS_TYPE" == "msys"* || "$OS_TYPE" == "cygwin"* || "$OS_TYPE" == "mingw"* ]]; then
    PROJECT_ROOT="$(pwd -W)"  # convert Git Bash path to Windows style
else
    PROJECT_ROOT="$(pwd)"
fi
echo "$PROJECT_ROOT"

# Step 1: Build image
echo "-----------------------------"
echo "🚀 Step 1: Building image"

# Detect Docker OSType
DOCKER_OSTYPE=$(docker info --format '{{.OSType}}' 2>/dev/null || echo "unknown")

if [[ "$DOCKER_OSTYPE" == "linux" ]]; then
    BUILD_CMD="docker buildx build --platform linux/amd64 --load -t $IMAGE_NAME $APP_NAME"
    echo "[INFO] Docker Linux engine detected. Using buildx."
elif [[ "$DOCKER_OSTYPE" == "windows" ]]; then
    BUILD_CMD="docker build -t $IMAGE_NAME $APP_NAME"
    echo "[WARNING] Docker Windows engine detected. Building without --platform (Windows image)."
else
    echo "[ERROR] Could not detect Docker engine type. Is Docker running?"
    exit 1
fi

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
    -v "${PROJECT_PATH}:/app" \
    -p 8000:8000 \
    $IMAGE_NAME
echo "[SUCCESS] Container '$CONTAINER_NAME' is running."

echo "============================="
echo " 🎉 ${APP_NAME}'s container exited. Workflow finished."
echo "============================="