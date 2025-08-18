#!/bin/bash

echo "Generating load to trigger autoscaling..."
SERVICE_URL="localhost:8080"

kubectl port-forward svc/ai-model-service 8080:80 -n ai-model-demo &
PORTFORWARD_PID=$!
sleep 5

# Generate load with multiple concurrent requests
for i in {1..100}; do
    curl -s -X POST "http://$SERVICE_URL/predict" \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"Test message $i\"}" &
done

echo "Monitoring HPA scaling..."
watch kubectl get hpa -n ai-model-demo

kill $PORTFORWARD_PID