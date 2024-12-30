import base64
import os

def lambda_handler(event, context):
    # 環境変数から認証情報を取得
    username_env = os.environ.get("BASIC_AUTH_USERNAME")
    password_env = os.environ.get("BASIC_AUTH_PASSWORD")

    # Authorizationヘッダーの取得
    headers = event.get("headers", {})
    auth_header = headers.get("Authorization", {})

    # Authorizationヘッダーがない場合は拒否
    if not auth_header.startswith("Basic "):
        print("Missing or invalid Authorization header")
        return generate_policy("Deny", event["methodArn"])

    try:
        # ユーザー名とパスワードをデコード
        encoded_credentials = auth_header.split(" ")[1]
        decoded_credentials = base64.b64decode(encoded_credentials).decode("utf-8")
        username, password = decoded_credentials.split(":")
    except Exception as e:
        print("Error decoding credentials:", str(e))
        return generate_policy("Deny", event["methodArn"])

    # 認証情報の検証
    if username == username_env and password == password_env:
        print("Authentication successful")
        return generate_policy("Allow", event["methodArn"])
    else:
        print("Authentication failed")
        return generate_policy("Deny", event["methodArn"])


def generate_policy(effect, resource):
    """
    IAMポリシーを生成します。

    :param effect: "Allow" または "Deny"
    :param resource: メソッドARN
    """
    return {
        "principalId": "user",
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": effect,
                    "Resource": resource
                }
            ]
        }
    }