# InciLog v2 — アラーム対応管理ツール

インフラ運用現場で発生するアラームログを記録・分類・対応管理するためのWebアプリケーション。
過去の類似アラームを **ベクトル類似度検索（AI）** で自動的に見つけ出し、対応品質の均一化と対応時間の短縮を支援する。

> 旧版（v1）は「障害対応タイムライン記録ツール」でしたが、v2 で **アラームログ管理 + 意味ベースの類似検索** へと大きく刷新されました。

---

## 主な機能

| 機能 | 説明 |
|------|------|
| 🔔 アラームログ管理 | アラームの登録・一覧・絞込（ステータス / チーム / ホスト）・編集 |
| 🧠 類似ログ検索 | multilingual-e5（ONNX）+ pgvector による **意味ベース** の過去事例検索。文言が違っても同種の事象を発見 |
| 📋 対応テンプレート | メッセージコード・キーワード等に応じた対応手順テンプレートの自動提案 |
| 📥 一括取込 | Excel/監視ツールからのCSV/TSVをコピー＆ペーストで一括登録 |
| 🖥️ ホスト管理 | ホストマスタの登録・カテゴリ分類 |
| 📊 統計ダッシュボード | ステータス別・チーム別・ホスト別の集計 |
| 📤 Excel出力 | アラーム一覧を `.xlsx` でエクスポート |

### 類似ログ検索の仕組み

1. ログ登録時、`message` から埋め込みベクトル（1024次元）をバックグラウンドで生成し `log_embeddings` に保存
2. 検索時は対象ログを再ベクトル化し、**同一ホスト** かつ **対応内容（response）が記録済み** のログの中から
   コサイン類似度が閾値（既定 `0.75`）以上のものを類似度降順で返却
3. キーワード一致では拾えない「同じ事象を別の言葉で書いたログ」も発見できる

> 埋め込みモデルは外部ダウンロードせず、ローカルに配置した ONNX モデルを直接ロードします（社内・閉域環境でも安定動作）。

---

## アーキテクチャ

```
                       :8080
                    ┌────────┐
   User ───────────▶│ nginx  │  ← 唯一の外部公開ポート
                    └───┬────┘
                        │
               ┌────────┴────────┐
               │ /*              │ /api/*
          ┌────▼────┐       ┌────▼─────┐
          │frontend │       │ backend  │
          │React 19 │       │ FastAPI  │
          │ :3000   │       │  :8000   │
          └─────────┘       └────┬─────┘
                                 │ :5432
                            ┌────▼──────────┐
                            │      db        │
                            │ PostgreSQL 16  │
                            │  + pgvector    │
                            └────┬───────────┘
                                 │
                            [pgdata vol]
```

- すべてのコンテナは内部ネットワーク `incilog-net` で通信し、外部に公開されるのは nginx の `:8080` のみ
- backend は `./models` をリードオンリーでマウントし、ONNX 埋め込みモデルをロードする

---

## ディレクトリ構成

```
incilog/
├── docker-compose.yml          # 全コンテナのオーケストレーション
├── nginx/
│   └── default.conf            # L7リバースプロキシ設定
├── backend/
│   ├── Dockerfile
│   ├── requirements.txt        # FastAPI + onnxruntime + pgvector など
│   ├── main.py                 # FastAPI アプリ本体（API / ORM / Excel出力）
│   ├── embedding.py            # ONNX埋め込み生成（e5 / passage・query prefix）
│   └── scripts/
│       └── backfill.py         # 既存ログの埋め込み一括生成スクリプト
├── frontend/
│   ├── Dockerfile
│   ├── package.json            # React 19
│   └── src/App.js              # SPA本体（3ペインUI / 一括取込 / 統計）
├── db/
│   ├── 01_init.sql             # テーブル・インデックス定義
│   ├── 02_testdata.sql         # テストデータ（任意。削除で本番空DB構成）
│   └── 03_vector_migration.sql # pgvector拡張 + log_embeddings + HNSWインデックス
├── models/                     # ONNX埋め込みモデル配置先（要手動配置／git管理外）
└── docs/
    └── design.md               # 詳細設計書
```

---

## セットアップ

### 前提条件

| 項目 | 要件 |
|------|------|
| Docker Desktop | v4.0 以上（Docker Compose v2 同梱） |
| ポート | ホストの `8080`（Web）と `5433`（DB直接接続用）が空いていること |
| メモリ | 4GB 以上推奨（ONNX推論のため） |

### 1. 埋め込みモデルの配置

類似ログ検索を使うには、`multilingual-e5-large` の ONNX モデルを `models/` 配下に配置します。

```
models/
└── multilingual-e5-large-onnx/
    ├── model.onnx
    ├── model.onnx_data
    ├── tokenizer.json
    ├── tokenizer_config.json
    ├── special_tokens_map.json
    ├── sentencepiece.bpe.model
    └── config.json
```

> モデル未配置でもアプリは起動します。その場合、埋め込み生成はスキップされ、類似ログ検索は空の結果を返します（他機能は通常通り利用可能）。後からモデルを配置し、バックフィル（下記）を実行すれば有効化できます。

### 2. 起動

```bash
docker compose up --build
```

ブラウザで **http://localhost:8080** にアクセス。

起動確認:

```bash
curl http://localhost:8080/api/health
# → {"status":"ok","db":"connected"}
```

---

## 使い方

### アラームの登録
- 画面上の「＋追加」から、発生日時・ホスト名・メッセージなどを入力して登録
- 登録時にメッセージから `message_code` / `event_keyword` 等を自動抽出し、埋め込みベクトルも自動生成

### 一括取込（CSV/TSVペースト）
Excel や監視ツールの出力をヘッダ行ごとコピーし、取込画面のテキストエリアに貼り付けます（タブ/カンマ区切りを自動判定）。

| 列名（日本語） | 列名（英語） | 必須 |
|----------------|-------------|------|
| イベント登録日 | event_date | ✅ |
| イベント登録時刻 | event_time | （省略時 00:00:00） |
| イベント発行元ホスト名 | hostname | ✅ |
| メッセージ | message | ✅ |
| 担当T | team | |
| 対応内容 | response | |
| 担当者 | assignee | |
| 確認者 | reviewer | |

### 類似ログの参照
ログ一覧でログを選択すると、右ペインに過去の類似アラーム（対応内容つき）が類似度スコア付きで表示されます。過去の対応をそのまま参考にできます。

### 対応の記録とテンプレート
編集（✏️）から、対応内容・担当者・確認者・ステータス（未対応 → 対応済 → 完了）を記録。
ログの属性に一致する対応テンプレートが自動提案され、ワンクリックで挿入できます。

### Excel出力
「Excel出力」から、期間・チームで絞り込んだアラーム一覧を `.xlsx` でダウンロードできます。

---

## 運用コマンド

```bash
# バックグラウンド起動 / 停止
docker compose up -d
docker compose down

# ログ確認
docker compose logs -f backend

# 既存ログの埋め込みを一括生成（モデルを後から配置した場合など）
docker compose exec backend python -m scripts.backfill

# DBへ直接接続
docker compose exec db psql -U incilog -d incilog
# ホストからは: psql -h localhost -p 5433 -U incilog -d incilog

# DBを完全初期化（データ全削除して再構築）
docker compose down -v && docker compose up --build
```

### テストデータの切り替え
- **あり（デモ・開発用）**: `db/02_testdata.sql` を残したまま起動
- **なし（本番・空DB）**: `db/02_testdata.sql` を削除してから `docker compose down -v && docker compose up`

---

## API エンドポイント

ベースパス: `/api`　Swagger UI: `http://localhost:8080/api/docs`

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/health` | ヘルスチェック（DB疎通含む） |
| GET | `/api/logs` | アラームログ一覧（`status` / `team` / `host` / `limit` / `offset` で絞込） |
| POST | `/api/logs` | アラームログ登録（埋め込みを自動生成） |
| GET | `/api/logs/{id}` | ログ詳細 |
| PATCH | `/api/logs/{id}` | ログ更新（対応内容・担当者・ステータス等） |
| GET | `/api/logs/{id}/similar` | 類似ログ検索（ベクトル類似度） |
| GET | `/api/logs/{id}/suggest-templates` | 対応テンプレート候補 |
| GET | `/api/logs/export` | Excel出力（`date_from` / `date_to` / `team`） |
| GET | `/api/hosts` | ホスト一覧 |
| POST | `/api/hosts` | ホスト登録 |
| GET | `/api/templates` | テンプレート一覧 |
| POST | `/api/templates` | テンプレート登録 |
| GET | `/api/stats` | 統計（ステータス別・チーム別・ホスト別） |

---

## 技術スタック

| レイヤー | 技術 |
|----------|------|
| リバースプロキシ | nginx (alpine) |
| フロントエンド | React 19 |
| バックエンド | FastAPI / Uvicorn (Python 3.12) |
| データベース | PostgreSQL 16 + **pgvector**（HNSWインデックス） |
| 埋め込みモデル | multilingual-e5（ONNX Runtime, ローカルロード） |
| コンテナ基盤 | Docker Compose v2 |

---

## 環境変数（backend）

| 変数 | 既定値 | 説明 |
|------|--------|------|
| `DATABASE_URL` | `postgresql://incilog:incilog_pass@db:5432/incilog` | DB接続文字列 |
| `SIMILARITY_THRESHOLD` | `0.75` | 類似と判定するコサイン類似度の下限 |
| `EMBEDDING_MODEL` | `intfloat/multilingual-e5-large` | モデル識別ラベル（追跡用） |
| `EMBEDDING_MODEL_DIR` | `/app/models/multilingual-e5-large-onnx` | ONNXモデルの配置先 |

---

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| 類似ログが常に空 | `models/` にONNXモデルを配置し、`docker compose exec backend python -m scripts.backfill` を実行 |
| `pip` / `npm` で SSL エラー | 企業プロキシ対応として Dockerfile に `--trusted-host` / `strict-ssl false` を設定済み |
| ポート8080でアクセス不可 | 他サービスがポート使用中。`docker compose down` 後にポートを確認 |
| フロント変更が反映されない | `docker compose build --no-cache frontend` |
| backend 起動直後のDB接続エラー | healthcheck連鎖で自動回復するため待機すればOK |

詳細な設計・仕様は [`docs/design.md`](docs/design.md) を参照してください。
