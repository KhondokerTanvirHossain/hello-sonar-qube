# AWS SonarQube Automation Guide - From Local to Cloud

## Overview
This guide will help you migrate your local SonarQube setup to AWS using ECS (Elastic Container Service) with full automation using Infrastructure as Code (IaC).

## Architecture Overview
```
Internet → ALB → ECS Fargate (SonarQube) → RDS PostgreSQL
                                        ↓
                                    EFS (Persistent Storage)
```

## Prerequisites
- AWS CLI installed and configured
- Terraform installed (Infrastructure as Code tool)
- Your local SonarQube working (as per your README)

## Step 1: AWS Account Setup

### 1.1 Install AWS CLI
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure with your credentials
aws configure
```

### 1.2 Create IAM User (if needed)
- Go to AWS Console → IAM → Users → Create User
- Attach policies: `AmazonECS_FullAccess`, `AmazonRDS_FullAccess`, `AmazonVPC_FullAccess`

## Step 2: Infrastructure as Code with Terraform

### 2.1 Install Terraform
```bash
# Download and install Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### 2.2 Create Project Structure
```
aws-sonarqube/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── vpc.tf
│   ├── rds.tf
│   ├── ecs.tf
│   └── alb.tf
├── scripts/
│   └── deploy.sh
└── README.md
```

## Step 3: Terraform Configuration Files

### 3.1 Main Configuration (main.tf)
```hcl
# Add random provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}
```

### 3.2 Variables (variables.tf)
```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "sonarqube"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}

variable "db_password" {
  description = "Database password (auto-generated if not provided)"
  type        = string
  default     = ""
  sensitive   = true
}
```

### 3.3 VPC Configuration (vpc.tf)
```hcl
# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Subnets
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Private Route Table (for private subnets)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

# ECR Repository for SonarQube
resource "aws_ecr_repository" "sonarqube" {
  name                 = "${var.project_name}-sonarqube"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-sonarqube-ecr"
  }
}

# ECR Repository Policy (allows ECS to pull)
resource "aws_ecr_repository_policy" "sonarqube" {
  repository = aws_ecr_repository.sonarqube.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSPull"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# VPC Endpoints for ECR (so private subnets can access ECR without internet)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ecr-dkr-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ecr-api-endpoint"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-logs-endpoint"
  }
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-vpc-endpoints-sg"
  }
}
```

### 3.4 RDS Configuration (rds.tf)
```hcl
# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# Random password for RDS
resource "random_password" "db_password" {
  length  = 16
  special = true
  # Exclude problematic characters for RDS
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# AWS Secrets Manager secret for database password
resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.project_name}-db-password"
  description = "Database password for SonarQube RDS instance"

  tags = {
    Name = "${var.project_name}-db-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = "sonarqube"
    password = random_password.db_password.result
  })
}

# RDS Instance
resource "aws_db_instance" "sonarqube" {
  identifier = "${var.project_name}-db"

  engine         = "postgres"
  engine_version = "15.7"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = "sonarqube"
  username = "sonarqube"
  password = random_password.db_password.result

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "${var.project_name}-db"
  }
}
```

### 3.5 ECS Configuration (ecs.tf)
```hcl
# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ecs-tasks-sg"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "sonarqube" {
  family                   = "${var.project_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "2048"
  memory                   = "4096"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "sonarqube"
    image = "sonarqube:lts-community"

      portMappings = [
        {
          containerPort = 9000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "SONAR_JDBC_URL"
          value = "jdbc:postgresql://${aws_db_instance.sonarqube.endpoint}/sonarqube"
        },
        {
          name  = "SONAR_JDBC_USERNAME"
          value = "sonarqube"
        },
        {
          name  = "SONAR_JDBC_PASSWORD"
          value = random_password.db_password.result
        },
        {
          name  = "SONAR_ES_BOOTSTRAP_CHECKS_DISABLE"
          value = "true"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.sonarqube.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:9000/api/system/status | grep -q UP || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 300
      }
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "sonarqube" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.sonarqube.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id  # TEMPORARY: Use public subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true  # TEMPORARY: Assign public IP
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.sonarqube.arn
    container_name   = "sonarqube"
    container_port   = 9000
  }

  depends_on = [aws_lb_listener.sonarqube]
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "sonarqube" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
}

# IAM Roles
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the default ECS task execution policy
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional ECR permissions for task execution role
resource "aws_iam_role_policy" "ecs_task_execution_ecr" {
  name = "${var.project_name}-ecs-task-execution-ecr-policy"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}
```

### 3.6 Application Load Balancer (alb.tf)
```hcl
# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "sonarqube" {
  name        = "${var.project_name}-tg"
  port        = 9000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 60
    interval            = 300
    path                = "/api/system/status"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

# ALB Listener
resource "aws_lb_listener" "sonarqube" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sonarqube.arn
  }
}
```

### 3.7 Outputs (outputs.tf)
```hcl
output "sonarqube_url" {
  description = "SonarQube URL"
  value       = "http://${aws_lb.main.dns_name}"
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.sonarqube.endpoint
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "database_secret_arn" {
  description = "ARN of the database secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "database_password_command" {
  description = "Command to retrieve database password"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.db_password.name} --query SecretString --output text | jq -r '.password'"
}
```

## Step 4: Deployment Script

### 4.1 Create deploy.sh
```bash
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
```

## Step 5: Deployment Steps

### 5.1 Prepare Your Environment
```bash
# Create project directory
mkdir aws-sonarqube
cd aws-sonarqube

# Create terraform directory
mkdir terraform scripts

# Copy all the .tf files to terraform/ directory
# Copy deploy.sh to scripts/ directory
```

### 5.2 Make Script Executable
```bash
chmod +x scripts/deploy.sh
```

### 5.3 Deploy
```bash
./scripts/deploy.sh
```

## Step 6: Post-Deployment

### 6.1 Verify Deployment
```bash
# Check ECS service status
aws ecs describe-services --cluster sonarqube-cluster --services sonarqube-service

# Check task status
aws ecs list-tasks --cluster sonarqube-cluster --service-name sonarqube-service
```

### 6.2 Access SonarQube
- Wait 5-10 minutes for the service to fully start
- Access the URL provided in the deployment output
- Login with admin/admin
- Change the password when prompted

## Step 7: Cost Optimization Tips

### 7.1 Development Environment
- Use `db.t3.micro` for RDS (included in free tier)
- Use Fargate with minimal CPU/Memory
- Consider stopping the service when not in use

### 7.2 Scheduled Start/Stop
```bash
# Stop ECS service
aws ecs update-service --cluster sonarqube-cluster --service sonarqube-service --desired-count 0

# Start ECS service
aws ecs update-service --cluster sonarqube-cluster --service sonarqube-service --desired-count 1
```

## Step 8: Cleanup
When you're done testing:
```bash
cd terraform
terraform destroy -var="db_password=your_password_here"
```

## Troubleshooting

### Common Issues:
1. **ECS Task Won't Start**: Check CloudWatch logs
2. **Database Connection Issues**: Verify security groups
3. **ALB Health Check Fails**: SonarQube takes time to start (5-10 minutes)

### Useful Commands:
```bash
# View ECS logs
aws logs tail /ecs/sonarqube --follow

# Check RDS connectivity
aws rds describe-db-instances --db-instance-identifier sonarqube-db
```

## Next Steps
1. Set up CI/CD integration
2. Configure custom quality gates
3. Add HTTPS with SSL certificate
4. Set up backup strategies
5. Implement monitoring and alerting

This setup gives you a production-ready, scalable SonarQube instance on AWS that automatically handles scaling, security, and high availability!