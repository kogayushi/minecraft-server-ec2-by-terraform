output "api_gateway_id" {
  value = "https://${aws_api_gateway_rest_api.lambda_api.id}.execute-api.ap-northeast-1.amazonaws.com/production/minecraft-server/start"
}