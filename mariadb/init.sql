-- データベースとユーザーの作成
CREATE DATABASE todoapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'todoapp'@'%' IDENTIFIED BY 'todoapp';
GRANT ALL PRIVILEGES ON todoapp.* TO 'todoapp'@'%';
GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'todoapp'@'%';
FLUSH PRIVILEGES;

-- テーブルの作成
USE todoapp;

CREATE TABLE todos (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  done BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_done (done),
  INDEX idx_created_at (created_at)
) ENGINE=InnoDB;

-- サンプルデータの投入
INSERT INTO todos (title, done) VALUES
  ('Alloy をインストールする', TRUE),
  ('LGTM スタックを起動する', FALSE),
  ('ダッシュボードを作成する', FALSE),
  ('ログ収集を設定する', FALSE),
  ('トレースを確認する', FALSE);
