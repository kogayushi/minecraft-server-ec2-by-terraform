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
  user_data     = file("${path.module}/ec2_user_data.sh")
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

# Lambda Function for EC2 Management
data "archive_file" "ec2_starter_lambda_function_payload" {
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
  source_code_hash = data.archive_file.ec2_starter_lambda_function_payload.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      EC2_INSTANCE_ID = aws_instance.minecraft_server.id
    }
  }
}
# Lambda Permissions for CloudWatch Logs
resource "aws_lambda_permission" "ec2_manager_allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_manager.function_name
  principal     = "events.amazonaws.com"
}


# Lambda Function for Basic Authentication
data "archive_file" "basic_auth_lambda_function_payload" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/basic_auth"
  output_path = "${path.module}/build/basic_auth/lambda_function_payload.zip"
}

resource "aws_lambda_function" "basic_auth_authorizer" {
  filename         = "${path.module}/build/basic_auth/lambda_function_payload.zip"
  function_name    = "basic-auth-authorizer"
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  role             = aws_iam_role.lambda_ec2_role.arn

  environment {
    variables = {
      BASIC_AUTH_USERNAME = var.basic_auth_username
      BASIC_AUTH_PASSWORD = var.basic_auth_password
    }
  }
}

resource "aws_api_gateway_rest_api" "lambda_api" {
  name        = "minecraft-server-api"
  description = "API for managing Minecraft server using RESTful API"
}

# Lambdaリソースとメソッド
resource "aws_api_gateway_resource" "minecraft_server" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  parent_id   = aws_api_gateway_rest_api.lambda_api.root_resource_id
  path_part   = "minecraft-server"
}

resource "aws_api_gateway_resource" "minecraft_server_start" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  parent_id   = aws_api_gateway_resource.minecraft_server.id
  path_part   = "start"
}

resource "aws_api_gateway_method" "start_method" {
  rest_api_id   = aws_api_gateway_rest_api.lambda_api.id
  resource_id   = aws_api_gateway_resource.minecraft_server_start.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.basic_auth.id
}

# API Gateway Integration
resource "aws_api_gateway_integration" "start_integration" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  resource_id = aws_api_gateway_resource.minecraft_server_start.id
  http_method = aws_api_gateway_method.start_method.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.ec2_manager.invoke_arn
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "allow_apigateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_manager.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.lambda_api.execution_arn}/*"
}

# API Gateway Authorizer for Basic Auth
resource "aws_api_gateway_authorizer" "basic_auth" {
  name                   = "BasicAuthAuthorizer"
  rest_api_id            = aws_api_gateway_rest_api.lambda_api.id
  authorizer_uri         = "arn:aws:apigateway:ap-northeast-1:lambda:path/2015-03-31/functions/${aws_lambda_function.basic_auth_authorizer.arn}/invocations"
  type                   = "REQUEST"
  identity_source        = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 0
}

# デプロイメント
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id

  depends_on = [
    aws_api_gateway_method.start_method,
    aws_api_gateway_integration.start_integration
  ]
}

# Productionステージ
resource "aws_api_gateway_stage" "production" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.lambda_api.id
  stage_name    = "production"
  description   = "Production stage"
}

resource "aws_lambda_permission" "allow_apigateway_authorizer" {
  statement_id  = "AllowExecutionFromAPIGatewayAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.basic_auth_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.lambda_api.execution_arn}/*"
}