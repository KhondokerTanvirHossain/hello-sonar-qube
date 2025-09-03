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