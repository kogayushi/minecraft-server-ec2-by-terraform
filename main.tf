# EC2 Instance
resource "aws_security_group" "minecraft_server" {
  name        = "minecraft-server"
  description = "Allow inbound traffic on port 25565"

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 25565
    to_port   = 25565
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "minecraft_server" {
  ami           = "ami-018a608de9486664d"
  instance_type = "t4g.small"
  key_name      = "minecraft-server"
  user_data = file("${path.module}/ec2_user_data.sh")
  tags = {
    Name = "minecraft_server"
  }

  security_groups = [aws_security_group.minecraft_server.name]
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_ec2_role" {
  name = "lambda-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy to allow starting EC2
resource "aws_iam_policy" "lambda_ec2_policy" {
  name        = "lambda-ec2-policy"
  description = "Allows Lambda to manage EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:StartInstances",
          "ec2:DescribeInstances"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "lambda_ec2_attach" {
  role       = aws_iam_role.lambda_ec2_role.name
  policy_arn = aws_iam_policy.lambda_ec2_policy.arn
}

# Lambda Function
data "archive_file" "lambda_function_payload" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/ec2_starter"
  output_path = "${path.module}/build/ec2_starter/lambda_function_payload.zip"
}
resource "aws_lambda_function" "ec2_manager" {
  filename         = "${path.module}/build/ec2_starter/lambda_function_payload.zip"
  function_name    = "ec2-manager"
  role             = aws_iam_role.lambda_ec2_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_function_payload.output_base64sha256
  timeout          = 30
  environment {
    variables = {
      EC2_INSTANCE_ID = aws_instance.minecraft_server.id
    }
  }
}

# Lambda Permissions for CloudWatch Logs
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_manager.function_name
  principal     = "events.amazonaws.com"
}

# API Gateway
resource "aws_apigatewayv2_api" "lambda_api" {
  name          = "u5kg-minecraft-server-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.lambda_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ec2_manager.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "POST /minecraft-server/start"

  target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.lambda_api.id
  name        = "production"
  auto_deploy = true
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "allow_apigateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_manager.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*"
}