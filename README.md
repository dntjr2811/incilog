# InciLog - インフラ障害対応タイムライン記録ツール

SIer現場での障害対応タイムラインをリアルタイムに記録し、障害報告書を自動生成するWebアプリケーション。

## アーキテクチャ

```
                    :80
                 ┌────────┐
  User ────────▶ │ nginx  │
                 └───┬────┘
                     │
            ┌────────┴────────┐
            │ /*              │ /api/*
       ┌────▼────┐      ┌────▼────┐
       │frontend │      │backend  │
       │ React   │      │ FastAPI │
       │ :3000   │      │ :8000   │
       └─────────┘      └────┬────┘
                             │ :5432
                        ┌────▼────┐
                        │   db    │
                        │ Postgres│
                        └─────────┘
                             │
                        [pgdata vol]
```

## ディレクトリ構成

```
incilog/
├── docker-compose.yml
├── nginx/
│   └── default.conf          # リバースプロキシ設定
├── backend/
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── requirements.txt
│   └── main.py               # FastAPI アプリケーション
├── frontend/
│   ├── Dockerfile
│   └── (React アプリ)
└── db/
    └── init.sql               # 初期スキーマ + サンプルデータ
```

## 起動方法

```bash
docker compose up --build
```

ブラウザで http://localhost にアクセス。

## API エンドポイント

| Method | Path | 説明 |
|--------|------|------|
| GET | /api/health | ヘルスチェック |
| GET | /api/incidents | 障害一覧 |
| POST | /api/incidents | 障害作成 |
| GET | /api/incidents/:id | 障害詳細 |
| PATCH | /api/incidents/:id | 障害更新 |
| GET | /api/incidents/:id/events | タイムライン取得 |
| POST | /api/incidents/:id/events | イベント追加 |
| GET | /api/incidents/:id/report | Excel報告書出力 |
| GET | /api/assignees | 担当者一覧 |
| POST | /api/assignees | 担当者追加 |

## 技術スタック

- **nginx** : リバースプロキシ (L7ルーティング)
- **React 18** : タイムラインUI
- **FastAPI** : REST API
- **PostgreSQL 16** : データ永続化
- **Docker Compose** : コンテナオーケストレーション
