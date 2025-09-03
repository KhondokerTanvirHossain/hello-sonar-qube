#!/bin/bash

set -e

echo "🚀 Starting SonarQube AWS Deployment with ECR..."

# Check prerequisites
for cmd in terraform docker aws jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ $cmd is not installed. Please install it first."
        exit 1
    fi
done

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured. Run 'aws configure' first."
    exit 1
fi

# Navigate to terraform directory
cd terraform

# Initialize Terraform
echo "📦 Initializing Terraform..."
terraform init

# Plan the deployment
echo "📋 Planning deployment..."
terraform plan

# Ask for confirmation
read -p "Do you want to proceed with the deployment? (yes/no): " -r
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "🏗️  Deploying infrastructure..."
    terraform apply -auto-approve
    
    echo "✅ Infrastructure deployed!"
    echo "🌐 SonarQube URL: $(terraform output -raw sonarqube_url)"
    echo ""
    echo "🔐 Database credentials are stored securely in AWS Secrets Manager"
    echo "📋 To retrieve database password:"
    echo "   $(terraform output -raw database_password_command)"
    echo ""
    echo "⏳ Please wait 5-10 minutes for SonarQube to fully start up."
    echo "🔑 Default SonarQube login: admin/admin"
else
    echo "❌ Deployment cancelled"
fi