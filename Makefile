# ============================================================
# Grafana Alloy ハンズオン Makefile
# EC2 インスタンス上で使用する
# Usage:
#   make setup-db    (DBサーバーで実行)
#   make setup-web   (Webサーバーで実行)
#   make setup-admin (管理サーバーで実行)
# ============================================================

SHELL := /bin/bash

# ソフトウェアバージョン
GO_VERSION ?= 1.26.0

# リポジトリルート（クローン先）
REPO_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# ============================================================
# 共通ターゲット
# ============================================================

.PHONY: setup-hostname-web setup-hostname-db setup-hostname-admin
.PHONY: setup-web setup-db setup-admin
.PHONY: install-alloy-repo install-alloy setup-alloy-env-web setup-alloy-env-db setup-alloy-env-admin
.PHONY: start-alloy help

help: ## ヘルプを表示
	@echo "Usage:"
	@echo "  make setup-db       DBサーバーのセットアップ"
	@echo "  make setup-web      Webサーバーのセットアップ"
	@echo "  make setup-admin    管理サーバーのセットアップ"
	@echo ""
	@echo "Options:"
	@echo "  GO_VERSION=x.x.x         Goのバージョン (default: 1.26.0)"

# ------------------------------------------------------------
# ホスト名設定
# ------------------------------------------------------------

setup-hostname-web:
	sudo sed -i 's/preserve_hostname: false/preserve_hostname: true/' /etc/cloud/cloud.cfg
	sudo hostnamectl set-hostname todo-web
	@echo "==> ホスト名を todo-web に設定しました"

setup-hostname-db:
	sudo sed -i 's/preserve_hostname: false/preserve_hostname: true/' /etc/cloud/cloud.cfg
	sudo hostnamectl set-hostname todo-db
	@echo "==> ホスト名を todo-db に設定しました"

setup-hostname-admin:
	sudo sed -i 's/preserve_hostname: false/preserve_hostname: true/' /etc/cloud/cloud.cfg
	sudo hostnamectl set-hostname todo-admin
	@echo "==> ホスト名を todo-admin に設定しました"

# ------------------------------------------------------------
# Grafana Alloy (共通)
# ------------------------------------------------------------

install-alloy-repo:
	@echo "==> Grafana リポジトリを追加"
	@printf '[grafana]\nname=grafana\nbaseurl=https://rpm.grafana.com\nrepo_gpgcheck=1\nenabled=1\ngpgcheck=1\ngpgkey=https://rpm.grafana.com/gpg.key\nsslverify=1\nsslcacert=/etc/pki/tls/certs/ca-bundle.crt\n' | sudo tee /etc/yum.repos.d/grafana.repo > /dev/null

install-alloy: install-alloy-repo
	@echo "==> Grafana GPG 鍵をインポート"
	sudo rpm --import https://rpm.grafana.com/gpg.key
	@echo "==> Alloy をインストール"
	sudo dnf clean metadata --disablerepo="*" --enablerepo="grafana"
	sudo dnf -y install alloy

setup-alloy-env-web:
	@echo "==> Alloy 環境変数を設定 (Web)"
	@printf 'CUSTOM_ARGS="--stability.level=generally-available"\nCONFIG_FILE="/etc/alloy/config.alloy"\nALLOY_LGTM_OTELCOL_URL="10.0.1.30:4317"\nALLOY_PYROSCOPE_URL="http://10.0.1.30:4040"\n' | sudo tee /etc/sysconfig/alloy > /dev/null

setup-alloy-env-db:
	@echo "==> Alloy 環境変数を設定 (DB)"
	@printf 'CUSTOM_ARGS="--stability.level=generally-available"\nCONFIG_FILE="/etc/alloy/config.alloy"\nALLOY_LGTM_OTELCOL_URL="10.0.1.30:4317"\nALLOY_MYSQL_DSN="todoapp:todoapp@(localhost:3306)/todoapp"\nALLOY_PYROSCOPE_URL="http://10.0.1.30:4040"\n' | sudo tee /etc/sysconfig/alloy > /dev/null

setup-alloy-env-admin:
	@echo "==> Alloy 環境変数を設定 (Admin)"
	@printf 'CUSTOM_ARGS="--stability.level=generally-available"\nCONFIG_FILE="/etc/alloy/config.alloy"\nALLOY_LGTM_OTELCOL_URL="localhost:4317"\nALLOY_PYROSCOPE_URL="http://localhost:4040"\n' | sudo tee /etc/sysconfig/alloy > /dev/null

setup-alloy-override-web:
	@echo "==> Alloy systemd override を設定 (eBPF 用)"
	sudo mkdir -p /etc/systemd/system/alloy.service.d
	sudo cp $(REPO_DIR)/systemd/alloy-override.conf /etc/systemd/system/alloy.service.d/override.conf
	sudo systemctl daemon-reload

start-alloy:
	@echo "==> Alloy を起動"
	sudo systemctl restart alloy
	sudo systemctl enable alloy
	sudo systemctl status alloy --no-pager

# ============================================================
# DBサーバー (setup-db)
# ============================================================

install-mysql:
	@echo "==> MySQL をインストール"
	@if ! rpm -q mysql84-community-release > /dev/null 2>&1; then \
		sudo dnf -y install https://dev.mysql.com/get/mysql84-community-release-el9-3.noarch.rpm; \
		sudo sed -i 's/$$releasever/9/g' /etc/yum.repos.d/mysql-community*.repo; \
	else \
		echo "==> MySQL リポジトリは追加済み"; \
	fi
	sudo dnf -y install mysql-community-server

start-mysql:
	@echo "==> MySQL を起動"
	sudo systemctl start mysqld
	sudo systemctl enable mysqld

init-mysql:
	@echo "==> MySQL を初期設定"
	@if mysql -u root -proot -e "SELECT 1" > /dev/null 2>&1; then \
		echo "==> MySQL は初期設定済み (root パスワード確認OK)"; \
	else \
		TEMP_PASS=$$(sudo grep 'temporary password' /var/log/mysqld.log | tail -1 | awk '{print $$NF}'); \
		echo "==> 一時パスワード: $$TEMP_PASS"; \
		mysql -u root -p"$$TEMP_PASS" --connect-expired-password -e " \
			ALTER USER 'root'@'localhost' IDENTIFIED BY 'Temp_1234'; \
			UNINSTALL COMPONENT 'file://component_validate_password'; \
			ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';"; \
	fi
	@echo "==> アプリケーション用 DB を作成"
	@if mysql -u root -proot -e "USE todoapp; SELECT 1 FROM todos LIMIT 1" > /dev/null 2>&1; then \
		echo "==> todoapp データベースは作成済み"; \
	else \
		mysql -u root -proot < $(REPO_DIR)/mysql/init.sql; \
	fi
	@echo "==> todoapp ユーザーの権限を確認"
	@mysql -u root -proot -e "GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'todoapp'@'%'; FLUSH PRIVILEGES;" 2>/dev/null || true

configure-mysql:
	@echo "==> MySQL の設定を変更 (bind-address, ログ)"
	@# /etc/my.cnf の [mysqld] セクションに設定を追記（chapter2.txt の手順と同じ）
	@if ! grep -q 'bind-address' /etc/my.cnf; then \
		sudo sed -i 's|^log-error=.*|# log-error=/var/log/mysqld.log|' /etc/my.cnf; \
		sudo sed -i '/^\[mysqld\]/a\bind-address = 0.0.0.0\n\nlog_error = /var/log/mysql/error.log\nslow_query_log = 1\nslow_query_log_file = /var/log/mysql/slow.log\nlong_query_time = 0' /etc/my.cnf; \
	else \
		echo "==> MySQL の設定は追記済み"; \
	fi
	sudo mkdir -p /var/log/mysql
	sudo chown mysql:mysql /var/log/mysql
	sudo systemctl restart mysqld

verify-mysql:
	@echo "==> MySQL の動作確認"
	sudo systemctl status mysqld --no-pager
	mysql -u todoapp -ptodoapp -e "USE todoapp; SELECT COUNT(*) AS todo_count FROM todos;"

setup-db: setup-hostname-db install-mysql start-mysql init-mysql configure-mysql verify-mysql install-alloy setup-alloy-env-db
	@echo "==> Alloy ユーザーを mysql グループに追加"
	sudo usermod -aG mysql alloy
	@echo "==> Alloy 設定ファイルをコピー (DB)"
	sudo cp $(REPO_DIR)/alloy/db-config.alloy /etc/alloy/config.alloy
	$(MAKE) start-alloy
	@echo ""
	@echo "============================================"
	@echo " DBサーバーのセットアップが完了しました"
	@echo "============================================"

# ============================================================
# Webサーバー (setup-web)
# ============================================================

install-nginx:
	@echo "==> nginx をインストール"
	sudo dnf -y install nginx

install-go:
	@echo "==> Go $(GO_VERSION) をインストール"
	@if /usr/local/go/bin/go version 2>/dev/null | grep -q "go$(GO_VERSION)"; then \
		echo "==> Go $(GO_VERSION) はインストール済み"; \
	else \
		wget -q https://go.dev/dl/go$(GO_VERSION).linux-amd64.tar.gz -O /tmp/go.tar.gz; \
		sudo rm -rf /usr/local/go; \
		sudo tar -C /usr/local -xzf /tmp/go.tar.gz; \
		rm -f /tmp/go.tar.gz; \
	fi
	@grep -q '/usr/local/go/bin' $(HOME)/.bashrc || echo 'export PATH=$$PATH:/usr/local/go/bin' >> $(HOME)/.bashrc
	@echo "==> Go インストール完了: $$(/usr/local/go/bin/go version)"

build-app:
	@echo "==> ToDoApp をビルド"
	mkdir -p $(HOME)/app
	cp $(REPO_DIR)/app/main.go $(HOME)/app/main.go
	cd $(HOME)/app && \
		test -f go.mod || PATH=$$PATH:/usr/local/go/bin go mod init todoapp; \
		PATH=$$PATH:/usr/local/go/bin go mod tidy; \
		PATH=$$PATH:/usr/local/go/bin go build -o todoapp main.go

setup-todoapp-service:
	@echo "==> ToDoApp の systemd ユニットを設定"
	sudo cp $(REPO_DIR)/systemd/todoapp.service /etc/systemd/system/todoapp.service
	sudo systemctl daemon-reload
	sudo systemctl restart todoapp
	sudo systemctl enable todoapp
	sudo systemctl status todoapp --no-pager

configure-nginx:
	@echo "==> nginx を設定"
	sudo cp $(REPO_DIR)/nginx/default /etc/nginx/conf.d/todoapp.conf
	@# nginx.conf のデフォルト server ブロックを確実にコメントアウト（ネスト対応・冪等）
	@sudo awk ' \
		/^[[:space:]]*server[[:space:]]*\{/ && !in_server && !/^#/ { in_server=1; depth=0 } \
		in_server { \
			n=split($$0, c, ""); \
			for(i=1;i<=n;i++){ if(c[i]=="{")depth++; if(c[i]=="}")depth-- } \
			if($$0 !~ /^#/) printf "#%s\n", $$0; else print; \
			if(depth<=0) in_server=0; \
			next \
		} \
		{ print }' /etc/nginx/nginx.conf > /tmp/nginx.conf.tmp \
		&& sudo mv /tmp/nginx.conf.tmp /etc/nginx/nginx.conf \
		&& sudo chmod 644 /etc/nginx/nginx.conf
	sudo nginx -t
	sudo systemctl restart nginx
	sudo systemctl enable nginx

verify-web:
	@echo "==> Web サーバーの動作確認"
	curl -s http://localhost/health && echo ""

setup-web: setup-hostname-web install-nginx install-go build-app setup-todoapp-service configure-nginx verify-web install-alloy setup-alloy-env-web setup-alloy-override-web
	@echo "==> Alloy 設定ファイルをコピー (Web)"
	sudo cp $(REPO_DIR)/alloy/web-config.alloy /etc/alloy/config.alloy
	$(MAKE) start-alloy
	@echo ""
	@echo "============================================"
	@echo " Webサーバーのセットアップが完了しました"
	@echo "============================================"

# ============================================================
# 管理サーバー (setup-admin)
# ============================================================

install-docker:
	@echo "==> Docker をインストール"
	sudo dnf -y install docker
	sudo systemctl start docker
	sudo systemctl enable docker
	sudo usermod -aG docker $$USER

setup-lgtm:
	@echo "==> LGTM スタックを起動"
	mkdir -p $(HOME)/lgtm/container-data/{grafana,loki,prometheus,pyroscope,tempo}
	@if docker ps --format '{{.Names}}' | grep -q '^lgtm$$'; then \
		echo "==> LGTM コンテナは既に起動中"; \
	else \
		docker rm -f lgtm 2>/dev/null || true; \
		docker run \
			--name lgtm \
			-d \
			-p 4317:4317 \
			-p 4318:4318 \
			-p 3000:3000 \
			-p 4040:4040 \
			-p 9090:9090 \
			--restart unless-stopped \
			-v $(HOME)/lgtm/container-data/grafana:/data/grafana \
			-v $(HOME)/lgtm/container-data/loki:/loki \
			-v $(HOME)/lgtm/container-data/prometheus:/data/prometheus \
			-v $(HOME)/lgtm/container-data/pyroscope:/data/pyroscope \
			-v $(HOME)/lgtm/container-data/tempo:/data/tempo \
			-e GF_PATHS_DATA=/data/grafana \
			grafana/otel-lgtm:0.13.0; \
	fi

configure-tempo:
	@echo "==> Tempo の設定を変更 (vParquet4)"
	@if [ -f $(HOME)/lgtm/tempo-config.yaml ] && grep -q 'version: vParquet4' $(HOME)/lgtm/tempo-config.yaml; then \
		echo "==> Tempo 設定は変更済み"; \
	else \
		docker cp lgtm:/otel-lgtm/tempo-config.yaml $(HOME)/lgtm/tempo-config.yaml; \
		sed -i '/path: \/data\/tempo\/blocks/a\    block:\n      version: vParquet4' $(HOME)/lgtm/tempo-config.yaml; \
	fi
	docker rm -f lgtm 2>/dev/null || true
	docker run \
		--name lgtm \
		-d \
		-p 4317:4317 \
		-p 4318:4318 \
		-p 3000:3000 \
		-p 4040:4040 \
		-p 9090:9090 \
		--restart unless-stopped \
		-v $(HOME)/lgtm/container-data/grafana:/data/grafana \
		-v $(HOME)/lgtm/container-data/loki:/loki \
		-v $(HOME)/lgtm/container-data/prometheus:/data/prometheus \
		-v $(HOME)/lgtm/container-data/pyroscope:/data/pyroscope \
		-v $(HOME)/lgtm/container-data/tempo:/data/tempo \
		-v $(HOME)/lgtm/tempo-config.yaml:/otel-lgtm/tempo-config.yaml \
		-e GF_PATHS_DATA=/data/grafana \
		grafana/otel-lgtm:0.13.0

verify-admin:
	@echo "==> LGTM スタックの動作確認"
	@echo "==> Grafana の起動を待機中..."
	@for i in $$(seq 1 30); do \
		if curl -s http://localhost:3000/api/health | grep -q ok; then \
			echo "==> Grafana 起動確認 OK"; \
			break; \
		fi; \
		sleep 2; \
	done

setup-admin: setup-hostname-admin install-docker
	@echo ""
	@echo "==> docker グループの反映のため sg コマンドで続行します"
	sg docker -c "$(MAKE) setup-admin-docker"

setup-admin-docker: setup-lgtm configure-tempo verify-admin install-alloy setup-alloy-env-admin
	@echo "==> Alloy 設定ファイルをコピー (Admin)"
	sudo cp $(REPO_DIR)/alloy/admin-config.alloy /etc/alloy/config.alloy
	$(MAKE) start-alloy
	@echo ""
	@echo "============================================"
	@echo " 管理サーバーのセットアップが完了しました"
	@echo "============================================"
