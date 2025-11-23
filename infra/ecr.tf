resource "aws_ecr_repository" "hello_app" {
  name = "hello-app"
  image_scanning_configuration {
    scan_on_push = true
  }
}

output "ecr_repo_url" {
  value = aws_ecr_repository.hello_app.repository_url
}
