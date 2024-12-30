# 使い方
## 構築方法
1. aws-cliをインストールする
2. aws configureなどの方法でアクセスキーとシークレットキーを設定する
3. terraformをインストールする
4. `terraform init`を実行する
5. `terraform apply -var "basic_auth_username=your_username" -var "basic_auth_password=your_password"`を実行する

## 削除方法
1. `terraform destroy -var "basic_auth_username=your_username" -var "basic_auth_password=your_password"`を実行する
