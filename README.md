<div align="center">

# 🚨 InciLog v2

### AIが「過去の似たアラーム」を自動で見つけてくれる、アラーム対応管理ツール

インフラ運用現場で日々大量に発生するアラーム。
**「これ、前にも似たようなのあったよな…どう対応したっけ？」**
— その記憶頼みの作業を、AIによる類似検索で一瞬に変えるツールです。

</div>

---

## 🎯 何ができる？（3行で）

1. **記録する** — アラームを登録すると、内容を自動で分類・保存します。
2. **AIが探す** — 過去ログの中から「意味が似ているアラーム」をAIが自動で見つけ、当時の対応内容ごと表示します。
3. **すぐ対応** — 過去の対応をそのまま参考にできるので、調査時間が激減します。

> 💡 **キモは「意味で探す」こと。**
> ただのキーワード検索ではなく、AI（言語モデル）が文章の *意味* を理解して似たログを探します。
> だから **言い回しが違っても、同じ事象なら見つけられます。**

---

## ✨ AI類似検索が「すごい」ところ

従来のキーワード検索は、文字が一致しないと拾えません。InciLogは違います。

```
🔍 いま発生したアラーム:
   "ディスク残量が逼迫しています (/var/log 残り8%)"

        │  AIが「意味」で検索（文字が違ってもOK）
        ▼

✅ AIが見つけた過去の似たアラーム（対応内容つき）:

   類似度 0.91  "ファイルシステム /var/log の空き容量が閾値を下回りました"
              → 対応: 古いローテートログを削除し、logrotate設定を見直し。担当:鈴木

   類似度 0.86  "Disk usage on /var/log reached 92%"
              → 対応: 監視閾値を90%へ調整。アプリのデバッグログ出力を抑制。担当:山田
```

👉 **「逼迫」「空き容量」「Disk usage」** ── 言葉はバラバラなのに、
**「ディスクが足りない」という同じ意味** だとAIが理解して、全部見つけ出します。

---

## 🧠 仕組み（どうやってAIで探しているのか）

InciLogは、文章を **AIで数値ベクトル（意味の座標）に変換** し、その座標が近いものを「似ている」と判断します。

```
┌─────────────────────── ① 登録するとき ───────────────────────┐
│                                                              │
│   アラーム本文                                               │
│   "ディスク残量が逼迫…"                                      │
│        │                                                     │
│        ▼                                                     │
│   ┌──────────────────────┐    意味を1024個の数値に変換       │
│   │  🧠 AI埋め込みモデル  │  ───────────────────────►        │
│   │  multilingual-e5      │    [0.12, -0.84, 0.33, … ]       │
│   │  (ONNX / ローカル実行)│                                  │
│   └──────────────────────┘         │                        │
│                                     ▼                        │
│                          ┌────────────────────┐             │
│                          │ 🗄️ pgvector (DB)    │ ← ベクトルを │
│                          │  ベクトルを保存     │   保存       │
│                          └────────────────────┘             │
└──────────────────────────────────────────────────────────────┘

┌─────────────────────── ② 検索するとき ───────────────────────┐
│                                                              │
│   選んだアラーム ──► 🧠 AIでベクトル化 ──► 🗄️ pgvectorに      │
│                                            「近いベクトル」を  │
│                                            問い合わせ         │
│                                                 │            │
│                                                 ▼            │
│              コサイン類似度が高い順に、対応済みの             │
│              似たアラームを返す（同一ホスト内で絞込）         │
└──────────────────────────────────────────────────────────────┘
```

**ポイント**

| 項目 | 内容 |
|------|------|
| 使用AIモデル | `multilingual-e5-large`（多言語対応の文埋め込みモデル / 日本語◎） |
| 実行方式 | **ONNX Runtimeでローカル実行**。外部APIもクラウドも不要。閉域・社内環境でも動く |
| ベクトル検索 | PostgreSQL の **pgvector拡張**（HNSWインデックスで高速近傍検索） |
| 似ている判定 | コサイン類似度が **しきい値（既定 0.75）以上** のものだけ採用 |
| 検索範囲の絞込 | まず **同じホスト** かつ **対応内容が記録済み** のログに限定 → ノイズを排除 |

---

## 🏗️ システム構成

すべて Docker Compose で動く4つのコンテナ構成。外部に公開されるのは入口の nginx だけです。

```
                          ブラウザ
                             │
                             │  http://localhost:8080
                             ▼
                      ┌─────────────┐
                      │   🌐 nginx   │   ← 唯一の公開ポート (8080)
                      │ リバースプロキシ│      入口でルーティング
                      └──────┬──────┘
                  /*         │          /api/*
            ┌────────────────┴────────────────┐
            ▼                                  ▼
   ┌─────────────────┐              ┌──────────────────────┐
   │  🖥️ frontend     │              │  ⚙️ backend           │
   │  React 19 (SPA)  │              │  FastAPI (Python)     │
   │  画面・操作UI    │              │  API・業務ロジック     │
   └─────────────────┘              └──────┬─────────┬──────┘
                                           │         │
                          埋め込み生成 ◄───┘         │ SQL / ベクトル検索
                                  │                  ▼
                      ┌───────────────────┐  ┌──────────────────────┐
                      │ 🧠 AI埋め込みモデル │  │  🗄️ db                │
                      │ multilingual-e5    │  │  PostgreSQL 16        │
                      │ (ONNX, ローカル)   │  │  + pgvector (ベクトルDB)│
                      └───────────────────┘  └──────────┬───────────┘
                       backendに同梱・              [pgdata] データ永続化
                       ./models をマウント
```

| コンテナ | 役割 | 技術 |
|----------|------|------|
| 🌐 **nginx** | 入口。`/api/*`はbackendへ、それ以外はfrontendへ振り分け | nginx (alpine) |
| 🖥️ **frontend** | 操作画面（一覧・登録・類似表示・統計） | React 19 |
| ⚙️ **backend** | API・AI埋め込み生成・Excel出力。AIモデルもここで動く | FastAPI / Python 3.12 / ONNX Runtime |
| 🗄️ **db** | ログ保存 ＋ **ベクトル検索エンジン** | PostgreSQL 16 + pgvector |

---

## 🚀 はじめかた（クイックスタート）

### 1. 前提

| 項目 | 要件 |
|------|------|
| Docker Desktop | v4.0 以上（Docker Compose v2 同梱） |
| 空きポート | `8080`（Web）と `5433`（DB直接接続用） |
| メモリ | 4GB 以上推奨（AI推論のため） |

### 2. AIモデルを置く

類似検索を使うには、AIモデル（ONNX形式）を `models/` に配置します。

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

> ⚠️ **モデルが無くてもアプリは起動します。** その場合、類似検索だけが空表示になり、他の機能（登録・一覧・Excel出力など）は通常通り使えます。
> 後からモデルを置いて、下記の **バックフィル** を実行すれば、既存ログも一括でAI検索対象になります。

### 3. 起動

```bash
docker compose up --build
```

ブラウザで 👉 **http://localhost:8080** へアクセス。

```bash
# 起動できたか確認
curl http://localhost:8080/api/health
# → {"status":"ok","db":"connected"}
```

---

## 📖 使い方

### 🔔 アラームを登録する
画面の「＋追加」から、発生日時・ホスト名・メッセージを入力。
登録と同時に、AIが裏側で自動的に内容をベクトル化します（操作は待たされません）。

### 📥 まとめて取り込む（Excelからコピペ）
監視ツールやExcelの表を **ヘッダ行ごとコピー** して、取込画面に貼り付けるだけ。タブ/カンマ区切りは自動判定します。

| 列名（日本語） | 列名（英語） | 必須 |
|----------------|-------------|:---:|
| イベント登録日 | event_date | ✅ |
| イベント登録時刻 | event_time | （省略時 00:00:00） |
| イベント発行元ホスト名 | hostname | ✅ |
| メッセージ | message | ✅ |
| 担当T | team | |
| 対応内容 | response | |
| 担当者 | assignee | |
| 確認者 | reviewer | |

### 🧠 似たアラームを参照する（メイン機能）
一覧でアラームを選ぶと、右側に **AIが見つけた過去の類似アラーム** が類似度スコア付きで並びます。
当時の「対応内容・担当者」もそのまま見えるので、調査せずに即対応できます。

### ✍️ 対応を記録する／テンプレートを使う
編集（✏️）から、対応内容・担当者・確認者・ステータス（🔴未対応 → 🟡対応済 → 🟢完了）を記録。
ログの種類に合った **対応テンプレートが自動提案** され、ワンクリックで挿入できます。

### 📤 Excelで出力する
期間・チームで絞り込んだアラーム一覧を `.xlsx` でダウンロードできます。

---

## 🛠️ よく使うコマンド

```bash
# 起動（バックグラウンド） / 停止
docker compose up -d
docker compose down

# ログを見る
docker compose logs -f backend

# 🧠 既存ログをまとめてAI検索対象にする（モデルを後から入れた時など）
docker compose exec backend python -m scripts.backfill

# DBに直接つなぐ
docker compose exec db psql -U incilog -d incilog
#   ホスト側からは: psql -h localhost -p 5433 -U incilog -d incilog

# DBを完全リセット（全データ削除して作り直し）
docker compose down -v && docker compose up --build
```

**テストデータの切り替え**
- デモ・お試し用 … `db/02_testdata.sql` を **残したまま** 起動
- 本番・空DB用 … `db/02_testdata.sql` を **削除してから** `docker compose down -v && docker compose up`

---

## 🔌 API一覧

ベースパス `/api` ／ Swagger UI: **http://localhost:8080/api/docs**

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/health` | ヘルスチェック（DB疎通含む） |
| GET | `/api/logs` | アラーム一覧（`status`/`team`/`host`/`limit`/`offset`で絞込） |
| POST | `/api/logs` | アラーム登録（AIベクトルを自動生成） |
| GET | `/api/logs/{id}` | アラーム詳細 |
| PATCH | `/api/logs/{id}` | アラーム更新（対応内容・担当者・ステータス等） |
| GET | `/api/logs/{id}/similar` | 🧠 **AI類似検索** |
| GET | `/api/logs/{id}/suggest-templates` | 対応テンプレート候補 |
| GET | `/api/logs/export` | Excel出力（`date_from`/`date_to`/`team`） |
| GET | `/api/hosts` | ホスト一覧 |
| POST | `/api/hosts` | ホスト登録 |
| GET | `/api/templates` | テンプレート一覧 |
| POST | `/api/templates` | テンプレート登録 |
| GET | `/api/stats` | 統計（ステータス別・チーム別・ホスト別） |

---

## ⚙️ 技術スタック

| レイヤー | 採用技術 |
|----------|----------|
| リバースプロキシ | nginx (alpine) |
| フロントエンド | React 19 |
| バックエンド | FastAPI / Uvicorn (Python 3.12) |
| **AI埋め込み** | **multilingual-e5-large**（ONNX Runtimeでローカル実行） |
| **ベクトルDB** | **PostgreSQL 16 + pgvector**（HNSWインデックス） |
| コンテナ基盤 | Docker Compose v2 |

### 環境変数（backend）

| 変数 | 既定値 | 説明 |
|------|--------|------|
| `DATABASE_URL` | `postgresql://incilog:incilog_pass@db:5432/incilog` | DB接続文字列 |
| `SIMILARITY_THRESHOLD` | `0.75` | この値以上の類似度だけを「似ている」と判定 |
| `EMBEDDING_MODEL` | `intfloat/multilingual-e5-large` | AIモデル識別ラベル |
| `EMBEDDING_MODEL_DIR` | `/app/models/multilingual-e5-large-onnx` | AIモデルの配置パス |

---

## 📁 ディレクトリ構成

```
incilog/
├── docker-compose.yml          # 4コンテナの構成定義
├── nginx/
│   └── default.conf            # 入口のルーティング設定
├── backend/                    # ⚙️ API + 🧠 AI
│   ├── main.py                 #   API本体・業務ロジック・Excel出力
│   ├── embedding.py            #   🧠 AI埋め込み生成（ONNX / e5）
│   ├── scripts/backfill.py     #   既存ログを一括ベクトル化
│   └── requirements.txt
├── frontend/                   # 🖥️ React 19 のSPA
│   └── src/App.js
├── db/                         # 🗄️ DB初期化スクリプト
│   ├── 01_init.sql             #   テーブル定義
│   ├── 02_testdata.sql         #   テストデータ（任意）
│   └── 03_vector_migration.sql #   pgvector拡張 + ベクトルテーブル
├── models/                     # 🧠 AIモデル置き場（手動配置 / git管理外）
└── docs/
    └── design.md               # 詳細設計書
```

---

## 🆘 困ったときは

| 症状 | 対処 |
|------|------|
| 類似アラームが常に空 | `models/` にAIモデルを置き、`docker compose exec backend python -m scripts.backfill` を実行 |
| `pip` / `npm` でSSLエラー | 社内プロキシ対応として Dockerfile に `--trusted-host` / `strict-ssl false` 設定済み |
| 8080でアクセスできない | 他サービスがポート使用中。`docker compose down` 後にポート確認 |
| 画面の変更が反映されない | `docker compose build --no-cache frontend` |
| 起動直後にDB接続エラー | healthcheck連鎖で自動回復。少し待てばOK |

> 📘 設計・仕様の詳細は [`docs/design.md`](docs/design.md) を参照してください。
