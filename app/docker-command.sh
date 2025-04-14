#!/bin/bash

# NOTE - BEFORE RUNNING THIS SCRIPT YOU MUST:
#
# 1. Make sure you are logged into Azure CLI with `az login`
# 2. Set the environment variable ACR_NAME to the name of your Azure Container Registry
# 3. Run this script from the root of the project directory

cd app/Consumer

echo "Logging into Azure Container Registry"
az acr login --name ${ACR_NAME}

echo "Building the RabbitMQ Consumer Docker image"
docker buildx build -t rabbitmq-consumer --platform=linux/amd64 .

echo "Tagging the RabbitMQ Consumer Docker image"
docker tag rabbitmq-consumer:latest ${ACR_NAME}.azurecr.io/houdemo/rabbitmq-consumer:latest

echo "Pushing the RabbitMQ Consumer Docker image to Azure Container Registry"
docker push ${ACR_NAME}.azurecr.io/houdemo/rabbitmq-consumer:latest