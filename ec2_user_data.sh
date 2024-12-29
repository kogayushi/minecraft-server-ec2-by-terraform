#!/bin/bash


MINECRAFTSERVERURL=https://piston-data.mojang.com/v1/objects/4707d00eb834b446575d89a61a11b5d548d8c001/server.jar

# 必要なパッケージのインストール
sudo yum install -y java-21-amazon-corretto-headless cronie

# Minecraftサーバーディレクトリの作成
adduser minecraft
mkdir -p /opt/minecraft/server
cd /opt/minecraft/server

cat <<EOF > eula.txt
eula=true
EOF

# サーバーのダウンロードとセットアップ
wget $MINECRAFTSERVERURL
chown -R minecraft:minecraft /opt/minecraft/

# スタート/ストップスクリプトの作成
cat <<'START_SCRIPT' > /opt/minecraft/server/start
#!/bin/bash
java -Xmx1300M -Xms1300M -jar server.jar nogui
START_SCRIPT
chmod +x /opt/minecraft/server/start

cat <<'STOP_SCRIPT' > /opt/minecraft/server/stop
#!/bin/bash
kill -9 $(pgrep -f "java -Xmx1300M")
STOP_SCRIPT
chmod +x /opt/minecraft/server/stop

# SystemDスクリプトの作成
cat <<'SYSTEMD_SCRIPT' > /etc/systemd/system/minecraft.service
[Unit]
Description=Minecraft Server
Wants=network-online.target

[Service]
User=minecraft
WorkingDirectory=/opt/minecraft/server
ExecStart=/opt/minecraft/server/start
Restart=on-failure
StandardInput=null

[Install]
WantedBy=multi-user.target
SYSTEMD_SCRIPT

systemctl daemon-reload
systemctl enable minecraft.service
systemctl start minecraft.service

# ログインユーザー確認スクリプトの作成
cat <<'CHECK_SCRIPT' > /usr/local/bin/check_minecraft_users.sh
#!/bin/bash

# ログファイルのパス
LOG_FILE="/opt/minecraft/server/logs/latest.log"

# 起動後15分はシャットダウンしない
FIRST_LINE=$(head -n 1 "$LOG_FILE")
START_TIME=$(echo "$FIRST_LINE" | awk '{print substr($1, 2, length($1)-2)}')
START_SECONDS=$(echo "$START_TIME" | awk -F: '{print ($1 * 3600) + ($2 * 60) + $3}')
CURRENT_TIME=$(date +"%H:%M:%S")
CURRENT_SECONDS=$(echo "$CURRENT_TIME" | awk -F: '{print ($1 * 3600) + ($2 * 60) + $3}')
TIME_DIFF=$((CURRENT_SECONDS - START_SECONDS))
if [ $TIME_DIFF -lt 0 ]; then
  TIME_DIFF=$((TIME_DIFF + 86400)) # 翌日のケースを考慮
fi

if [ $TIME_DIFF -lt 900 ]; then
  echo "Server is starting. Skipping shutdown check."
  exit 0
fi

# ログ解析
IN_COUNT=$(grep -c "joined the game" "$LOG_FILE")
OUT_COUNT=$(grep -c "left the game" "$LOG_FILE")

if [ $IN_COUNT -gt $OUT_COUNT ]; then
  echo "Players are online. No shutdown required."
else
  echo "No players online. Shutting down the server."
  sudo shutdown -h now
fi
CHECK_SCRIPT

chmod +x /usr/local/bin/check_minecraft_users.sh

# CRONジョブの設定
touch /var/log/check_minecraft_users.log
chmod 644 /var/log/check_minecraft_users.log
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/check_minecraft_users.sh >> /var/log/check_minecraft_users.log 2>&1") | crontab -
systemctl start crond
systemctl enable crond

# 終了
echo "Setup complete."