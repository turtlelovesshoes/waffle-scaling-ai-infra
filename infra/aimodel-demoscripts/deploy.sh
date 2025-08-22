#!/bin/bash

set -e

echo "Building Docker image..."
docker build -t ai-model-api:latest ./app/

echo "Creating namespace..."
kubectl apply -f k8s/namespace.yaml

echo "Deploying Redis..."
kubectl apply -f k8s/redis.yaml

echo "Waiting for Redis to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/redis -n ai-model-demo

echo "Deploying AI Model API..."
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

echo "Waiting for API to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/ai-model-api -n ai-model-demo

echo "Setting up autoscaling..."
kubectl apply -f k8s/hpa.yaml

echo "Deployment complete!"
echo "Getting service URL..."
kubectl get svc ai-model-service -n ai-model-demo
```

## 6. Test Script (test.sh)
```bash
#!/bin/bash

# Get service URL
SERVICE_URL=$(kubectl get svc ai-model-service -n ai-model-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$SERVICE_URL" ]; then
    echo "Using port-forward for testing..."
    kubectl port-forward svc/ai-model-service 8080:80 -n ai-model-demo &
    PORTFORWARD_PID=$!
    SERVICE_URL="localhost:8080"
    sleep 5
fi

echo "Testing API at http://$SERVICE_URL"

echo "1. Health check..."
curl -s "http://$SERVICE_URL/health" | jq .

echo "2. First prediction (cache miss)..."
curl -s -X POST "http://$SERVICE_URL/predict" \
    -H "Content-Type: application/json" \
    -d '{"text": "I love this product!"}' | jq .

echo "3. Same prediction (cache hit)..."
curl -s -X POST "http://$SERVICE_URL/predict" \
    -H "Content-Type: application/json" \
    -d '{"text": "I love this product!"}' | jq .

echo "4. Metrics..."
curl -s "http://$SERVICE_URL/metrics" | jq .

# Cleanup port-forward if used
if [ ! -z "$PORTFORWARD_PID" ]; then
    kill $PORTFORWARD_PID