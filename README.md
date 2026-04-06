# practical-observability-for-infra

書籍「インフラエンジニアのための実践オブザーバビリティ入門ガイド」のハンズオン用リポジトリです。

## 概要

被監視側でオブザーバビリティエージェントを使ってログ、メトリクス、トレース等の各種テレメトリーデータを収集し、それを管理サーバーに転送して集約し、管理サーバーで可視化します。

### システム構成

| サーバー | ホスト名 | 主なミドルウェア |
|----------|----------|------------------|
| Webサーバー | todo-web | nginx, ToDoアプリ (Go), Grafana Alloy |
| DBサーバー | todo-db | MariaDB, Grafana Alloy |
| 管理サーバー | todo-admin | otel-lgtm, Grafana Alloy |

## 前提条件

- AWSアカウントを持っていること
- CloudFormationスタックの作成・削除ができるIAM権限があること
- Session Managerでインスタンスに接続できること

## クイックスタート

### 1. インフラの構築

`cloudformation/handson-stack.yaml` を使ってCloudFormationスタックを東京リージョンに作成します。

パラメータの入力画面では、MyIpパラメータに接続元のパブリックIPアドレスをCIDR形式（例: 203.xxx.xxx.xxx/32）で入力してください（/32も必要です）。ブラウザまたはターミナルで http://checkip.amazonaws.com/ にアクセスするとIPアドレスを確認できます。

```
$ curl http://checkip.amazonaws.com/
```

AMI IDはデフォルト値のままで問題ありません。

### 2. 各サーバーにログインして初期設定

```bash
$ sudo su - ec2-user
$ sudo dnf upgrade
$ sudo dnf -y install git make
$ git clone https://github.com/kikulabo/practical-observability-for-infra.git ~/handson
```

### 3. makeコマンドでセットアップ

各サーバーで対応するコマンドを実行するだけで、ミドルウェアのインストールからAlloyの起動まで一括で行えます。

```bash
$ cd ~/handson
# Webサーバーで実行
$ make setup-web
# DBサーバーで実行
$ make setup-db
# 管理サーバーで実行
$ make setup-admin
```

## リポジトリ構成

```
.
├── alloy/                  # Grafana Alloyの設定ファイル
│   ├── web-config.alloy    #   Webサーバー用
│   ├── db-config.alloy     #   DBサーバー用
│   └── admin-config.alloy  #   管理サーバー用
├── app/                    # ToDoアプリケーション (Go)
├── cloudformation/         # AWS CloudFormationテンプレート
│   └── handson-stack.yaml
├── mariadb/                # MariaDB初期化SQL
├── nginx/                  # nginxリバースプロキシ設定
├── systemd/                # systemdユニットファイル
└── Makefile                # セットアップ自動化
```

## コマンドリファレンス

各章で必要なコマンドを順番に記載します。makeコマンドを使わずに手動でセットアップする場合は、以下のコマンドを順番に実行してください。

### 2-3. CloudFormationによるインフラ構築

接続元のパブリックIPアドレスを確認。

```
$ curl http://checkip.amazonaws.com/
```

ユーザー切り替え。

```
$ sudo su - ec2-user
```

コマンドのインストールとリポジトリのクローン。

```
# 各サーバーにログインし以下のコマンドを実行
$ sudo dnf upgrade
$ sudo dnf -y install git make
$ git clone https://github.com/kikulabo/practical-observability-for-infra.git ~/handson
```

### 2-4. ホスト名の設定（全サーバー共通）

```
# 各サーバーにログインし以下のコマンドを実行
$ sudo vim /etc/cloud/cloud.cfg
```

preserve_hostnameをfalseからtrueに書き換える。

```
preserve_hostname: true
```

ホスト名を設定。

```
# Webサーバーで実行
sudo hostnamectl set-hostname todo-web
# DBサーバーで実行
sudo hostnamectl set-hostname todo-db
# 管理サーバーで実行
sudo hostnamectl set-hostname todo-admin
```

設定したらSession Managerでインスタンスに接続し直すとホスト名が反映される。

### 2-5. DBサーバーのセットアップ

MariaDBをインストール

```
sudo dnf -y install mariadb1011-server
```

MariaDBを起動し自動起動を有効化

```
# DBサーバーで実行
$ sudo systemctl start mariadb
$ sudo systemctl enable mariadb
```

DBの初期設定

```
# DBサーバーで実行（rootユーザーからパスワードなしで接続できます）
$ sudo mysql -u root < ~/handson/mariadb/init.sql
```

mariadb-server.cnfを開く

```
# DBサーバーで実行
$ sudo vim /etc/my.cnf.d/mariadb-server.cnf
```

mysqldセクションに以下を追記

```
[mysqld]
bind-address = 0.0.0.0
slow-query-log = 1
slow-query-log-file = /var/log/mariadb/slow.log
long-query-time = 0
```

設定を反映するためMariaDBを再起動

```
# DBサーバーで実行
$ sudo systemctl restart mariadb
```

MariaDBの動作確認

```
# DBサーバーで実行
$ sudo systemctl status mariadb
# パスワードにtodoappと入力
$ mysql -u todoapp -p -e "USE todoapp; SELECT COUNT(*) AS todo_count FROM todos;"
```

### 2-6. Webサーバーのセットアップ

nginxをインストール

```
# Webサーバーで実行
$ sudo dnf -y install nginx
```

サンプルアプリケーションの準備

```
# Webサーバーで実行
$ mkdir -p ~/app
$ cp ~/handson/app/todoapp ~/app/todoapp
$ chmod +x ~/app/todoapp
```

todoapp.serviceをコピーして内容を確認

```
# Webサーバーで実行
$ sudo cp ~/handson/systemd/todoapp.service /etc/systemd/system/todoapp.service
$ cat /etc/systemd/system/todoapp.service
```

アプリケーションを起動

```
# Webサーバーで実行
$ sudo systemctl daemon-reload
$ sudo systemctl start todoapp
$ sudo systemctl enable todoapp
$ sudo systemctl status todoapp
```

nginxのリバースプロキシの設定

```
# Webサーバーで実行
$ sudo cp ~/handson/nginx/default /etc/nginx/conf.d/todoapp.conf
$ sudo vim /etc/nginx/nginx.conf
```

`/etc/nginx/nginx.conf` を開いたら以下の部分をコメントアウト
```
    server {
        listen       80;
        listen       [::]:80;
        server_name  _;
        root         /usr/share/nginx/html;

        # Load configuration files for the default server block.
        include /etc/nginx/default.d/*.conf;

        error_page 404 /404.html;
        location = /404.html {
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
        }
    }
```

Nginxの設定を反映して起動

```
# Webサーバーで実行
$ sudo nginx -t
$ sudo systemctl start nginx
$ sudo systemctl enable nginx
```

### 2-7. 管理サーバーのセットアップ

Dockerをインストール

```
# 管理サーバーで実行
$ sudo dnf -y install docker
$ sudo systemctl start docker
$ sudo systemctl enable docker
$ sudo usermod -aG docker $USER
```

otel-lgtmコンテナーを起動

```
# 管理サーバーで実行
$ mkdir -p ~/lgtm/container-data/{grafana,loki,prometheus,pyroscope,tempo}
$ cd ~/lgtm
$ docker run \
    --name lgtm \
    -d \
    -p 4317:4317 \
    -p 4318:4318 \
    -p 3000:3000 \
    -p 4040:4040 \
    -p 9090:9090 \
    --restart unless-stopped \
    -v $PWD/container-data/grafana:/data/grafana \
    -v $PWD/container-data/loki:/loki \
    -v $PWD/container-data/prometheus:/data/prometheus \
    -v $PWD/container-data/pyroscope:/data/pyroscope \
    -v $PWD/container-data/tempo:/data/tempo \
    -e GF_PATHS_DATA=/data/grafana \
    grafana/otel-lgtm:0.13.0
```

コンテナー内の設定ファイルを取り出す

```
# 管理サーバーで実行
$ docker cp lgtm:/otel-lgtm/tempo-config.yaml .
```

tempo-config.yamlを開いて `storage.trace` セクションに `block.version` を追記

```
vim tempo-config.yaml
```

```
 storage:
    trace:
      # ... 既存の設定 ...
      block:
        version: vParquet4
```

設定ファイルをマウントしてコンテナーを再起動

```
# 管理サーバーで実行
$ docker stop lgtm && docker rm lgtm
$ docker run \
  --name lgtm \
  -d \
  -p 4317:4317 \
  -p 4318:4318 \
  -p 3000:3000 \
  -p 4040:4040 \
  -p 9090:9090 \
  --restart unless-stopped \
  -v $PWD/container-data/grafana:/data/grafana \
  -v $PWD/container-data/loki:/loki \
  -v $PWD/container-data/prometheus:/data/prometheus \
  -v $PWD/container-data/pyroscope:/data/pyroscope \
  -v $PWD/container-data/tempo:/data/tempo \
  -v $PWD/tempo-config.yaml:/otel-lgtm/tempo-config.yaml \
  -e GF_PATHS_DATA=/data/grafana \
  grafana/otel-lgtm:0.13.0
```

### 2-8. Grafana Alloyのインストール

GrafanaのRPMリポジトリーを追加し、Alloyをインストール

```
# 全サーバーで実行
$ cat <<'EOF' | sudo tee /etc/yum.repos.d/grafana.repo
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=0
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
$ sudo rpm --import https://rpm.grafana.com/gpg.key
$ sudo dnf clean metadata --disablerepo="*" --enablerepo="grafana"
$ sudo dnf -y install alloy
```

alloyをroot権限で起動し必要なケイパビリティを付与

```
# Webサーバーで実行
$ sudo systemctl edit alloy
```

```
[Service]
  User=root
  Group=root
  LimitMEMLOCK=infinity
  AmbientCapabilities=CAP_SYS_ADMIN CAP_SYS_RESOURCE CAP_BPF CAP_PERFMON CAP_NET_ADMIN CAP_SYS_PTRACE
```

nanoエディターで保存して閉じる際は `Ctrl + X` 、`Y` 、`Enter` の順にキーを入力

### 2-9. 環境変数の設定

各サーバーの `/etc/sysconfig/alloy` 環境変数を設定

```
# Webサーバー
$ sudo tee /etc/sysconfig/alloy <<'EOF'
CUSTOM_ARGS="--stability.level=public-preview"
CONFIG_FILE="/etc/alloy/config.alloy"
ALLOY_LGTM_OTELCOL_URL="10.0.1.30:4317"
ALLOY_PYROSCOPE_URL="http://10.0.1.30:4040"
EOF

# DBサーバー
$ sudo tee /etc/sysconfig/alloy <<'EOF'
CUSTOM_ARGS="--stability.level=public-preview"
CONFIG_FILE="/etc/alloy/config.alloy"
ALLOY_LGTM_OTELCOL_URL="10.0.1.30:4317"
ALLOY_MARIADB_DSN="todoapp:todoapp@(localhost:3306)/todoapp"
ALLOY_PYROSCOPE_URL="http://10.0.1.30:4040"
EOF

# 管理サーバー
$ sudo tee /etc/sysconfig/alloy <<'EOF'
CUSTOM_ARGS="--stability.level=public-preview"
CONFIG_FILE="/etc/alloy/config.alloy"
ALLOY_LGTM_OTELCOL_URL="10.0.1.30:4317"
ALLOY_PYROSCOPE_URL="http://10.0.1.30:4040"
EOF
```

### 2-10. Alloyの設定ファイル

リポジトリーに含まれるAlloyの設定ファイルを、各サーバーの /etc/alloy/config.alloy にコピー
DBサーバーでは、AlloyがMariaDBのログファイルを読み取れるよう、alloyユーザーをmysqlグループに追加

```
# Webサーバー
$ sudo cp ~/handson/alloy/web-config.alloy /etc/alloy/config.alloy
# DBサーバー
$ sudo cp ~/handson/alloy/db-config.alloy /etc/alloy/config.alloy
$ sudo usermod -aG mysql alloy
# 管理サーバー
$ sudo cp ~/handson/alloy/admin-config.alloy /etc/alloy/config.alloy
```

Alloyを起動

```
# 全サーバーで実行
$ sudo systemctl start alloy
$ sudo systemctl enable alloy
$ sudo systemctl status alloy
```

### 4-3. メトリクスを見る：PromQL入門

upメトリクスを表示

```
up
```

CPUが各モードで過ごした合計秒数を表示

```
node_cpu_seconds_total
```

idleモードの時系列だけが表示

```
node_cpu_seconds_total{mode="idle"}
```

CPUのidle割合（0〜1）を表示

```
rate(node_cpu_seconds_total{mode="idle"}[5m])
```

CPU使用率を表示

```
1 - rate(node_cpu_seconds_total{mode="idle"}[5m])
```

利用可能メモリーの割合を表示

```
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
```

MariaDB接続数を表示

```
mysql_global_status_threads_connected
```

5分あたりのクエリー実行数を表示

```
rate(mysql_global_status_queries[5m])
```

### 4-4. ログを見る：LogQL入門

syslogのログを表示

```
{service_name="syslog"}
```

unitラベルで `todoapp.service` をフィルタリングして表示

```
{service_name="syslog"} | unit = "todoapp.service"
```

スロークエリーログを表示

```
{service_name="mariadb"} | type = "slow"
```

POSTリクエストのアクセスログだけを表示

```
{service_name="nginx"} |= "POST"
```

### 4-5. トレースを見る：TraceQL入門

すべてのトレースを表示

```
{}
```

POSTリクエストのトレースだけを表示

```
{span.http.request.method = "POST"}
```

/todosパスへのリクエストのみ表示

```
{span.url.path = "/todos"}
```

処理時間が2msを超えるトレースだけ表示

```
{duration > 2ms}
```

### 5-3. （仕込み）障害を発生させる

todosテーブルにREADロックをかける

```
$ sudo mysql -u root todoapp -e "LOCK TABLES todos READ; SELECT SLEEP(60);"
```

レスポンス確認

```
$ curl http://WEB_SERVER_PUBLIC_IP/todos
$ curl -X POST -d "title=ロック中のテスト" http://WEB_SERVER_PUBLIC_IP/todos
```

### 5-4. （分析）メトリクスで概況を把握する

CPU使用率を表示

```
1 - rate(node_cpu_seconds_total{mode="idle"}[5m])
```

MariaDBのクエリー実行数を表示

```
rate(mysql_global_status_queries[5m])
```

### 5-5. （分析）トレースで遅いリクエストを特定する

処理時間が10秒を超えるトレースだけ表示

```
{duration > 10s}
```

### 5-6. （分析）ログで原因を絞り込む

10秒以上時間がかかったスロークエリーログを表示

```
{service_name="mariadb"} | type = "slow" | query_time > 10
```


### 6-4. ネットワーク系コレクターを追加する

TCPソケットの割り当て数を表示

```
node_sockstat_TCP_alloc
```

TIME_WAIT状態のTCPソケット数を表示

```
node_sockstat_TCP_tw
```

Webサーバーに対してリクエストを繰り返し送る

```
for i in $(seq 1 100); do curl -s http://WEB_SERVER_PUBLIC_IP/health > /dev/null; done
```

TCPソケットが使用しているメモリー量を表示

```
node_sockstat_TCP_mem_bytes
```

Alloyの設定ファイルを編集

```
$ sudo vim /etc/alloy/config.alloy
```

`prometheus.exporter.unix` ブロックに `enable_collectors = ["buddyinfo"]` を追記

```
prometheus.exporter.unix "host" {
  include_exporter_metrics = true
  enable_collectors        = ["buddyinfo"]
}
```

Alloyを再起動

```
# Webサーバーで実行
$ sudo systemctl restart alloy
$ sudo systemctl status alloy
```

buddyinfoメトリクスを表示

```
node_buddyinfo_blocks
```

DMA32ゾーンのsize 0の空き数を表示

```
node_buddyinfo_blocks{zone="DMA32", size="0"}
```
