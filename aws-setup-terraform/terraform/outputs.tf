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

output "ecr_repository_url" {
  description = "ECR repository URL for SonarQube"
  value       = aws_ecr_repository.sonarqube.repository_url
}

output "ecr_push_commands" {
  description = "Commands to push SonarQube image to ECR"
  value = "docker pull sonarqube:lts-community && aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.sonarqube.repository_url} && docker tag sonarqube:lts-community ${aws_ecr_repository.sonarqube.repository_url}:latest && docker push ${aws_ecr_repository.sonarqube.repository_url}:latest"
}