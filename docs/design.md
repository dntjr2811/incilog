# InciLog — 詳細設計書

> **文書管理番号:** INCILOG-DD-001  
> **版数:** 2.0  
> **最終更新日:** 2026-04-15  
> **ステータス:** ローカル開発環境 稼働中

---

## 1. プロジェクト概要

### 1.1 目的

InciLogは、インフラ運用現場におけるアラーム対応業務を効率化するためのWebアプリケーションである。
監視システムから発報されるアラームログの記録・分類・対応履歴の管理を一元化し、過去の類似アラームの対応内容を参照することで、対応品質の均一化と対応時間の短縮を実現する。

### 1.2 解決する課題

| 課題 | 現状 | InciLogによる解決 |
|------|------|-------------------|
| アラーム対応記録の分散 | Excel・メール・チャットに分散し検索不可 | DB一元管理で即座に検索可能 |
| 過去事例の参照困難 | 担当者の記憶に依存 | 類似アラーム自動検索で過去対応を即表示 |
| 対応品質のばらつき | 担当者の経験に依存 | テンプレート機能で対応手順を標準化 |
| 一括取込の手間 | 監視ツールからのCSV/TSVを手動入力 | テキスト貼り付けで一括取込 |

### 1.3 技術スタック

| レイヤー | 技術 | バージョン | 選定理由 |
|----------|------|------------|----------|
| リバースプロキシ | nginx | alpine (最新) | 軽量、L7ルーティング、WebSocket対応 |
| フロントエンド | React | 18.x | SPA、リアルタイムUI更新 |
| バックエンド | FastAPI (Python) | 0.115+ | 自動APIドキュメント生成、型安全 |
| データベース | PostgreSQL | 16-alpine | ACID準拠、JSON対応、全文検索対応 |
| コンテナ基盤 | Docker Compose | v2 | ワンコマンドで全環境構築 |

---

## 2. システムアーキテクチャ

### 2.1 全体構成図

```
User (ブラウザ)
    │
    │ :8080
    ▼
┌─────────────────────────────────────────────┐
│            Docker Network                   │
│            incilog-net (bridge)              │
│                                             │
│   ┌──────────┐                              │
│   │  nginx   │ ← 唯一の外部公開ポート      │
│   │  :80     │                              │
│   └────┬─────┘                              │
│        │                                    │
│        ├── /api/* ──► ┌───────────┐         │
│        │              │ backend   │         │
│        │              │ FastAPI   │         │
│        │              │ :8000     │         │
│        │              └─────┬─────┘         │
│        │                    │               │
│        ├── /* ────► ┌───────┴─────┐         │
│        │            │ frontend    │         │
│        │            │ React       │         │
│        │            │ :3000       │         │
│        │            └─────────────┘         │
│        │                                    │
│        │              ┌───────────┐         │
│        │              │    db     │         │
│        │              │ PostgreSQL│         │
│        │              │ :5432     │         │
│        │              └─────┬─────┘         │
└─────────────────────────────┼───────────────┘
                              │
                         [pgdata]
                       Docker Volume
```

### 2.2 設計原則

| 原則 | 説明 |
|------|------|
| 単一公開ポート | nginxの:8080のみホストに公開。frontend/backend/dbは外部から直接アクセス不可 |
| コンテナ間通信 | Docker DNSによるサービス名解決（例: backend → db:5432）。IPアドレスのハードコーディング禁止 |
| データ永続化 | Named Volume `pgdata` によりコンテナ削除後もデータ保持 |
| ヘルスチェック連鎖 | db(pg_isready) → backend(/api/health) → nginx起動 の順序を保証 |
| テストデータ分離 | `02_testdata.sql` が存在すれば自動投入、削除すれば本番構成 |

### 2.3 ネットワーク構成

```
ホスト側:
  localhost:8080 ──► nginx コンテナ :80

Docker内部ネットワーク (incilog-net):
  nginx ──► frontend:3000  (/* へのリクエスト)
  nginx ──► backend:8000   (/api/* へのリクエスト)
  backend ──► db:5432      (PostgreSQL接続)
```

外部公開ポートを8080にした理由: ローカル開発環境において他サービス（K3s Traefik等）とのポート80競合を回避するためである。

---

## 3. ディレクトリ構成

```
incilog/
├── docker-compose.yml          … 全コンテナのオーケストレーション定義
├── .gitignore                  … Git管理対象外ファイル定義
│
├── nginx/
│   └── default.conf            … L7リバースプロキシ設定
│
├── backend/
│   ├── Dockerfile              … Python実行環境構築
│   ├── .dockerignore           … ビルド時除外ファイル
│   ├── requirements.txt        … Pythonパッケージ依存関係
│   └── main.py                 … FastAPI アプリケーション本体
│
├── frontend/
│   ├── Dockerfile              … Node.js/React実行環境構築
│   ├── .dockerignore           … ビルド時除外ファイル (node_modules必須)
│   ├── package.json            … Node.js依存関係
│   └── src/
│       ├── App.js              … Reactアプリケーション本体
│       └── App.css             … スタイルシート
│
├── db/
│   ├── 01_init.sql             … テーブル定義（スキーマのみ）
│   └── 02_testdata.sql         … テストデータ（任意: 削除で無効化）
│
└── docs/
    └── design.md               … 本設計書
```

---

## 4. データベース設計

### 4.1 ER図

```
┌──────────────┐       ┌──────────────────────────────────┐
│    hosts     │       │              logs                │
├──────────────┤       ├──────────────────────────────────┤
│ id        PK │◄──FK──│ host_id                          │
│ hostname  UQ │       │ id                            PK │
│ description  │       │ event_date                       │
│ category     │       │ event_time                       │
│ notes        │       │ message                          │
│ created_at   │       │ team                             │
└──────────────┘       │ response                         │
                       │ assignee                         │
                       │ reviewer                         │
                       │ status                           │
                       │ group_id                         │
                       │ message_code                     │
                       │ jobnet_path                      │
                       │ org_name                         │
                       │ source_device                    │
                       │ interface_no                     │
                       │ event_keyword                    │
                       │ jobnet_name                      │
                       │ created_at                       │
                       │ updated_at                       │
                       └──────────────────────────────────┘

┌──────────────────────────────────┐
│       response_templates         │
├──────────────────────────────────┤
│ id                            PK │
│ title                            │
│ content                          │
│ team                             │
│ match_host                       │
│ match_code                       │
│ match_device                     │
│ match_keyword                    │
│ created_at                       │
└──────────────────────────────────┘
```

### 4.2 テーブル定義

#### 4.2.1 hosts（ホストマスタ）

| カラム名 | データ型 | NULL | 制約 | 説明 |
|----------|----------|------|------|------|
| id | SERIAL | NO | PRIMARY KEY | 自動採番 |
| hostname | VARCHAR(50) | NO | UNIQUE | ホスト名（例: WEB-PROD-01） |
| description | VARCHAR(200) | YES | - | ホストの説明 |
| category | VARCHAR(50) | YES | - | カテゴリ（UI側のlocalStorageで管理） |
| notes | TEXT | YES | - | 備考・メモ |
| created_at | TIMESTAMPTZ | NO | DEFAULT NOW() | 登録日時 |

設計意図: categoryにCHECK制約を設けない理由は、カテゴリの追加・編集・削除をフロントエンド側のlocalStorageで柔軟に管理するためである。DB側で値を制限すると、カテゴリ追加のたびにALTER TABLEが必要となり運用コストが増大する。

#### 4.2.2 logs（アラームログ）

| カラム名 | データ型 | NULL | 制約 | 説明 |
|----------|----------|------|------|------|
| id | SERIAL | NO | PRIMARY KEY | 自動採番 |
| event_date | DATE | NO | - | イベント発生日 |
| event_time | TIME | NO | - | イベント発生時刻 |
| host_id | INTEGER | YES | FK → hosts(id) | 発生ホスト |
| message | TEXT | NO | - | アラームメッセージ本文 |
| team | VARCHAR(20) | YES | - | 担当チーム |
| response | TEXT | YES | - | 対応内容 |
| assignee | VARCHAR(200) | YES | - | 担当者（フリーテキスト） |
| reviewer | VARCHAR(200) | YES | - | 確認者（フリーテキスト） |
| status | VARCHAR(20) | NO | CHECK, DEFAULT 'new' | 対応状態 |
| group_id | INTEGER | YES | - | グループID（関連ログ紐付け用） |
| message_code | VARCHAR(30) | YES | - | メッセージコード（例: KAVS0265-E） |
| jobnet_path | VARCHAR(200) | YES | - | ジョブネットパス |
| org_name | VARCHAR(100) | YES | - | 組織名 |
| source_device | VARCHAR(50) | YES | - | 発生元機器名 |
| interface_no | VARCHAR(20) | YES | - | インターフェイス番号 |
| event_keyword | VARCHAR(50) | YES | - | イベントキーワード（例: linkDown） |
| jobnet_name | VARCHAR(200) | YES | - | ジョブネット名 |
| created_at | TIMESTAMPTZ | NO | DEFAULT NOW() | レコード作成日時 |
| updated_at | TIMESTAMPTZ | NO | DEFAULT NOW() | レコード更新日時 |

statusの値域:

| 値 | 表示 | 説明 |
|----|------|------|
| new | 🔴 未対応 | 初期状態。対応が必要 |
| responded | 🟡 対応済 | 対応内容が記録された |
| closed | 🟢 完了 | 確認者によりクローズ |

設計意図: assignee/reviewerをフリーテキストにした理由は、担当者マスタの初期構築コストを避け、運用開始を迅速化するためである。将来的にマスタ化する場合はFKに変更可能。

#### 4.2.3 response_templates（対応テンプレート）

| カラム名 | データ型 | NULL | 制約 | 説明 |
|----------|----------|------|------|------|
| id | SERIAL | NO | PRIMARY KEY | 自動採番 |
| title | VARCHAR(200) | NO | - | テンプレートタイトル |
| content | TEXT | NO | - | 対応内容テンプレート本文 |
| team | VARCHAR(20) | YES | - | 対象チーム |
| match_host | VARCHAR(50) | YES | - | ホスト名マッチ条件 |
| match_code | VARCHAR(30) | YES | - | メッセージコードマッチ条件 |
| match_device | VARCHAR(50) | YES | - | 機器名マッチ条件 |
| match_keyword | VARCHAR(50) | YES | - | キーワードマッチ条件 |
| created_at | TIMESTAMPTZ | NO | DEFAULT NOW() | 登録日時 |

### 4.3 インデックス設計

| インデックス名 | 対象テーブル | カラム | 目的 |
|----------------|------------|--------|------|
| idx_logs_host_id | logs | host_id | ホスト別ログ検索の高速化 |
| idx_logs_event_date | logs | event_date | 日付範囲検索の高速化 |
| idx_logs_status | logs | status | ステータスフィルタリング |
| idx_logs_team | logs | team | チーム別フィルタリング |
| idx_logs_message_code | logs | message_code | 類似ログ検索（業務系） |
| idx_logs_source_device | logs | source_device | 類似ログ検索（基盤系） |
| idx_logs_event_keyword | logs | event_keyword | 類似ログ検索（基盤系） |
| idx_logs_group_id | logs | group_id | グループ検索 |
| idx_logs_jobnet_path | logs | jobnet_path | ジョブネット検索 |

---

## 5. API設計

### 5.1 エンドポイント一覧

| メソッド | パス | 説明 | レスポンス |
|----------|------|------|-----------|
| GET | /api/health | ヘルスチェック | {status, db} |
| GET | /api/logs | ログ一覧取得 | {total, logs[]} |
| POST | /api/logs | ログ新規登録 | {id, hostname, status} |
| GET | /api/logs/{id} | ログ詳細取得 | ログオブジェクト |
| PATCH | /api/logs/{id} | ログ更新 | 更新済オブジェクト |
| GET | /api/logs/{id}/similar | 類似ログ検索 | {target_id, match_criteria, similar_logs[]} |
| GET | /api/logs/{id}/suggest-templates | テンプレート候補取得 | テンプレート配列 |
| GET | /api/logs/export | Excel出力 | .xlsxファイル |
| GET | /api/hosts | ホスト一覧取得 | ホスト配列 |
| POST | /api/hosts | ホスト新規登録 | {id, hostname} |
| PATCH | /api/hosts/{id} | ホスト更新 | 更新済オブジェクト |
| GET | /api/templates | テンプレート一覧 | テンプレート配列 |
| POST | /api/templates | テンプレート登録 | {id, title} |
| GET | /api/stats | 統計情報取得 | {total, new, responded, closed, by_team, top_hosts} |
| GET | /api/docs | Swagger UI | 自動生成APIドキュメント |

### 5.2 ログ一覧取得 (GET /api/logs)

クエリパラメータ:

| パラメータ | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| status | string | NO | ステータスフィルタ（new/responded/closed） |
| team | string | NO | チームフィルタ |
| host | string | NO | ホスト名フィルタ |
| limit | int | NO | 取得件数上限（デフォルト: 100） |

レスポンス例:
```json
{
  "total": 100,
  "logs": [
    {
      "id": 1,
      "event_date": "2026-04-15",
      "event_time": "09:15:22",
      "host_id": 1,
      "hostname": "WEB-PROD-01",
      "message": "WARNING: Disk usage on /var/log reached 92%",
      "team": "運用T",
      "status": "new",
      "response": null,
      "assignee": null,
      "reviewer": null,
      "message_code": null,
      "jobnet_path": null,
      "org_name": null,
      "source_device": null,
      "interface_no": null,
      "event_keyword": "disk_usage"
    }
  ]
}
```

### 5.3 類似ログ検索 (GET /api/logs/{id}/similar)

類似ログ検索は、対象ログのパース済みフィールドに基づいて過去の類似アラームを自動検索する機能である。

検索ロジック:

```
対象ログの属性を確認
  │
  ├── message_code が存在する場合
  │     → 同一 message_code を持つ過去ログを検索
  │
  ├── jobnet_path が存在する場合
  │     → 同一 jobnet_path を持つ過去ログを検索
  │
  ├── source_device が存在する場合
  │     → 同一 source_device を持つ過去ログを検索
  │
  ├── event_keyword が存在する場合
  │     → 同一 event_keyword を持つ過去ログを検索
  │
  └── いずれの属性も存在しない場合
        → 類似ログなし（空配列を返却）
```

設計意図: パース済みフィールドが一つも存在しないログ（自由テキストのみ）は、誤った類似検索結果を避けるために空配列を返す。以前のバージョンでは「同一ホストのログをfallbackで返す」仕様だったが、無関係なログが類似として表示されるバグの原因であったため削除した。

レスポンス例:
```json
{
  "target_id": 5,
  "match_criteria": {
    "message_code": null,
    "jobnet_path": null,
    "source_device": "NW-CORE-01",
    "event_keyword": "linkDown"
  },
  "similar_count": 3,
  "similar_logs": [
    {
      "id": 2,
      "event_date": "2026-03-01",
      "hostname": "NW-CORE-01",
      "message": "SNMP Trap: Interface GigabitEthernet0/1 link down",
      "response": "対向サーバのNIC再起動による一時的な切断。5秒後にlinkUp確認。",
      "assignee": "鈴木",
      "reviewer": "山田"
    }
  ]
}
```

### 5.4 テンプレート自動提案 (GET /api/logs/{id}/suggest-templates)

ログ編集時に、対象ログの属性に一致するテンプレートを自動的に候補として提示する。

マッチング条件:
- match_code と ログの message_code が一致
- match_device と ログの source_device が一致
- match_keyword と ログの event_keyword が一致
- match_host と ログの hostname が一致

いずれか一つでもマッチすれば候補として返却する。

### 5.5 ヘルスチェック (GET /api/health)

```json
{"status": "ok", "db": "connected"}
```

docker-compose.ymlのhealthcheckがこのエンドポイントを30秒間隔で呼び出す。
アプリケーションの生存確認だけでなく、DB接続の疎通確認まで行う。

---

## 6. フロントエンド設計

### 6.1 画面構成

```
┌──────────────────────────────────────────────────────────┐
│ [ログ管理]  アラーム対応管理ツール    [25 未対応] [75 対応済] │
├──────────────────────────────────────────────────────────┤
│ 🔔 アラームログ │ 🖥️ ホスト管理 │ 👥 チーム管理 │ 📋 テンプレート │ 📊 統計 │
├──────────────────────────────────────────────────────────┤
│                    （各タブのコンテンツ）                     │
└──────────────────────────────────────────────────────────┘
```

### 6.2 アラームログ画面（メイン画面）

3ペイン構成:

```
┌─────────────────┬───────────────────────────────────────────────────┐
│                 │  Detail Column (flex:3)  │  Similar Column (flex:4) │
│   ログ一覧      │ ┌─────────────────────┐   ┌─────────────────────┐  │
│   (固定幅360px) │ │ 詳細ログ①           │───│ 類似(3) ▼全3件      │  │
│                 │ ├─────────────────────┤   │ 類似ログカード1     │  │
│  ☑ 2026-04-15  │ │ 詳細ログ②           │   │ 類似ログカード2     │  │
│    WEB-PROD-01  │ ├─────────────────────┤   │ 類似ログカード3     │  │
│                 │ │ 詳細ログ③           │   └─────────────────────┘  │
│  ☐ 2026-04-14  │ ├─────────────────────┤                            │
│    DB-PROD-01   │ │ 詳細ログ④           │───┌─────────────────────┐  │
│                 │ └─────────────────────┘   │ 類似(1)             │  │
│  ☐ 2026-04-13  │                           │ 類似ログカード1     │  │
│    BATCH-01     │                           └─────────────────────┘  │
└─────────────────┴───────────────────────────────────────────────────┘
```

#### SVG曲線接続

選択したログに類似アラームが存在する場合、DetailカードとSimilarグループの間にSVG曲線（ベジェ曲線）を描画する。

実装方式:
- `useRef` で各カードのDOM要素を参照
- `getBoundingClientRect()` で座標を計算
- `requestAnimationFrame` でデバウンスし、スクロール・リサイズ時に再計算
- SVGは `position: absolute` で connected-container の上に重ねる
- `width/height` を `scrollWidth/scrollHeight` で動的設定し、スクロール領域全体をカバー

設計意図: MutationObserverは使用しない。DOMの変更を検知してcurveを再計算する際、setCurvesによるstate更新が再レンダリングを引き起こし、それがさらにMutationObserverを発火させる無限ループが発生するためである。代わりに、編集ボタンや折りたたみボタンのイベントハンドラから明示的にcalcCurvesを呼び出す方式を採用した。

#### 類似グループ折りたたみ

類似ログが複数件ある場合、初期状態では1件のみ表示し「▼ 全N件」ボタンで展開可能。

### 6.3 フィルタ・検索機能

| フィルタ | 方式 | 説明 |
|----------|------|------|
| メッセージ検索 | クライアントサイド | message/response/hostnameの部分一致 |
| ステータス | サーバサイド | APIのクエリパラメータ |
| チーム | サーバサイド | APIのクエリパラメータ |
| ホスト | サーバサイド | APIのクエリパラメータ |

### 6.4 一括取込機能（CSV/TSVペースト）

Excelからヘッダ行ごとコピー&ペーストで一括登録が可能。

対応カラム名:

| 日本語カラム名 | 英語カラム名 | 必須 |
|----------------|-------------|------|
| イベント登録日 | event_date | YES |
| イベント登録時刻 | event_time | NO (デフォルト: 00:00:00) |
| イベント発行元ホスト名 | hostname | YES |
| メッセージ | message | YES |
| 担当T | team | NO |
| 対応内容 | response | NO |
| 担当者 | assignee | NO |
| 確認者 | reviewer | NO |

処理フロー:
```
テキストエリアに貼り付け
  → 1行目をヘッダとして認識（タブ区切り or カンマ区切り自動判定）
  → プレビュー表示（先頭3件）
  → 「取込実行」ボタンで順次API呼び出し
  → 成功/失敗件数を表示
```

### 6.5 ローカルストレージ管理項目

| キー | 内容 | デフォルト値 |
|------|------|-------------|
| incilog_categories | ホストカテゴリ一覧 | ['Web','AP','DB','NW','VM','Batch','Backup','Mail','Storage','Infra','監視','other'] |
| incilog_teams | チーム一覧 | ['運用T','開発T','セキュリティT'] |

設計意図: カテゴリとチームをlocalStorageで管理する理由は、これらの情報がDB上のデータ参照整合性に関与しないため、マスタテーブルの追加によるCRUD工数増加を回避するためである。チーム管理画面から追加・編集・削除が可能で、変更は即座に全ドロップダウンに反映される。

### 6.6 ログ詳細編集画面

編集ボタン（✏️）クリック時のフィールド:

| フィールド | 入力形式 | 説明 |
|-----------|---------|------|
| 担当者 | テキスト | 自由入力 |
| 確認者 | テキスト | 自由入力 |
| ステータス | セレクト | new / responded / closed |
| 対応内容 | テキストエリア | 複数行入力可。テンプレート挿入対応 |

編集時の状態管理:
- `useEffect` の依存配列は `[log.id]` のみ
- log.response等の変更を依存に含めると、fetchLogs後のstate更新で編集中のフォームがリセットされる無限ループが発生するため意図的に除外

---

## 7. Dockerコンテナ設計

### 7.1 docker-compose.yml 構成

```yaml
services:
  nginx:      # L7リバースプロキシ
  frontend:   # React開発サーバ
  backend:    # FastAPI + Uvicorn
  db:         # PostgreSQL 16

volumes:
  pgdata:     # DBデータ永続化

networks:
  incilog-net:  # 内部ブリッジネットワーク
```

### 7.2 各コンテナ詳細

#### nginx

| 項目 | 値 |
|------|-----|
| イメージ | nginx:alpine |
| 公開ポート | 8080:80 |
| volumes | ./nginx/default.conf → /etc/nginx/conf.d/default.conf (ro) |
| 起動条件 | frontend: started, backend: healthy |

ルーティング規則:
- `/api/*` → backend:8000 （proxy_pass、X-Real-IP等ヘッダ付与）
- `/*` → frontend:3000 （WebSocket upgrade対応含む）

#### backend

| 項目 | 値 |
|------|-----|
| ベースイメージ | python:3.12-slim |
| ポート | 8000（コンテナ内部のみ） |
| 環境変数 | DATABASE_URL, TZ=Asia/Tokyo |
| 起動条件 | db: healthy |
| ヘルスチェック | curl -f http://localhost:8000/api/health (30秒間隔) |

Dockerfileの工夫:
- requirements.txtを先にCOPYしpip installすることでレイヤーキャッシュを活用
- SSL証明書検証を無視する設定（--trusted-host）を含む: 企業プロキシ環境対応
- curl をインストール: healthcheckのCMDで使用

#### frontend

| 項目 | 値 |
|------|-----|
| ベースイメージ | node:20-alpine |
| ポート | 3000（コンテナ内部のみ） |
| 環境変数 | REACT_APP_API_URL=/api |
| .dockerignore | node_modules（必須: ビルド時間を数分→数十秒に短縮） |

#### db

| 項目 | 値 |
|------|-----|
| イメージ | postgres:16-alpine |
| ポート | 5432（コンテナ内部のみ） |
| 環境変数 | POSTGRES_USER=incilog, POSTGRES_PASSWORD=incilog_pass, POSTGRES_DB=incilog |
| volumes | pgdata:/var/lib/postgresql/data, ./db:/docker-entrypoint-initdb.d (ro) |
| ヘルスチェック | pg_isready -U incilog (10秒間隔) |

initdb実行順序:
1. `01_init.sql` — テーブル・インデックス作成
2. `02_testdata.sql` — テストデータ投入（ファイルが存在する場合のみ）

---

## 8. テストデータ仕様

### 8.1 概要

| データ種別 | 件数 |
|-----------|------|
| ホスト | 20件 |
| 対応テンプレート | 12件 |
| アラームログ | 100件 |

### 8.2 ホストマスタ（20件）

| ホスト名 | 説明 | カテゴリ |
|----------|------|----------|
| WEB-PROD-01 / 02 | 本番Webサーバ (nginx) | Web |
| AP-PROD-01 / 02 | 本番APサーバ (Tomcat) | AP |
| DB-PROD-01 / 02 | 本番DBサーバ (PostgreSQL) | DB |
| BATCH-01 | バッチ処理サーバ | Batch |
| MON-01 | 統合監視サーバ (Zabbix) | 監視 |
| NW-CORE-01 | コアスイッチ (Catalyst) | NW |
| NW-DIST-01 | ディストリビューションSW | NW |
| FW-01 | ファイアウォール (FortiGate) | NW |
| LB-01 | ロードバランサ (F5 BIG-IP) | NW |
| MAIL-01 | メールサーバ (Postfix) | Mail |
| FILE-01 | ファイルサーバ (Samba) | Storage |
| BK-01 | バックアップサーバ (Veeam) | Backup |
| VM-HOST-01 / 02 | 仮想基盤ホスト (ESXi) | VM |
| DNS-01 | DNSサーバ (BIND) | Infra |
| NTP-01 | NTPサーバ | Infra |
| PROXY-01 | プロキシサーバ (Squid) | Infra |

### 8.3 アラームログ分類（100件）

| カテゴリ | 件数 | event_keyword例 | 内容 |
|----------|------|-----------------|------|
| ディスク使用率 | 10 | disk_usage | /var/log, /var/lib/postgresql等の閾値超過 |
| CPU/メモリ | 12 | cpu_high, memory_high | プロセス暴走、ヒープ不足、OOM Killer |
| ネットワーク | 15 | linkDown, linkUp | SNMP Trap、ポートフラッピング、ISP瞬断 |
| サービス停止 | 12 | service_down, ssl_expire | nginx/tomcat/postfix等の停止、SSL証明書期限 |
| バッチジョブ | 15 | backup_fail | ETL失敗、バックアップ失敗、ディスクフル |
| VMware | 10 | vm_ha | vCLS再起動、ハートビート喪失、HA再起動 |
| 認証/セキュリティ | 12 | auth_fail | SSH認証失敗、ブルートフォース、IPS検知 |
| バックアップ | 6 | backup_fail | Veeamジョブ失敗、容量不足 |
| DNS/インフラ基盤 | 8 | - | ゾーン転送失敗、NTP同期異常、Zabbixトリガー |

### 8.4 チーム割り当て

| チーム名 | 件数 | 対象 |
|----------|------|------|
| 運用T | 85件 | インフラ基盤全般 |
| 開発T | 15件 | バッチジョブ・アプリケーション関連 |
| セキュリティT | 12件 | 認証失敗・不正アクセス関連 |

---

## 9. 構築・デプロイ手順

### 9.1 前提条件

| 項目 | 要件 |
|------|------|
| OS | Windows 10/11, macOS, Linux |
| Docker Desktop | v4.0以上 |
| Docker Compose | v2（Docker Desktopに同梱） |
| ポート | 8080が未使用であること |
| メモリ | 4GB以上推奨 |

### 9.2 初回構築

```powershell
# 1. リポジトリクローン
git clone https://github.com/<ユーザ名>/incilog.git
cd incilog

# 2. 全コンテナビルド＆起動
docker compose up --build

# 3. 起動確認（別ターミナル）
curl http://localhost:8080/api/health
# → {"status":"ok","db":"connected"}

# 4. ブラウザでアクセス
# http://localhost:8080
```

### 9.3 日常運用コマンド

```powershell
# 起動
docker compose up -d

# 停止
docker compose down

# ログ確認
docker compose logs -f backend

# フロントエンド再ビルド（ソース変更後）
docker compose build --no-cache frontend
docker compose up

# DB初期化（テーブル・データ全削除して再作成）
docker compose down -v
docker compose up --build
```

### 9.4 テストデータの切り替え

```
テストデータあり（開発・デモ用）:
  db/02_testdata.sql が存在する状態で docker compose up

テストデータなし（本番・空DB）:
  db/02_testdata.sql を削除してから docker compose down -v && docker compose up
```

---

## 10. トラブルシューティング

### 10.1 既知の問題と対処

| 症状 | 原因 | 対処 |
|------|------|------|
| `pip install` で SSL エラー | 企業プロキシによるSSL検査 | Dockerfileに `--trusted-host` オプション追加済み |
| `npm install` で SSL エラー | 同上 | Dockerfileに `npm config set strict-ssl false` 追加済み |
| ポート8080でアクセス不可 | 他サービスがポート使用中 | `docker compose down` → ポート確認 → 再起動 |
| フロントエンド変更が反映されない | Docker ビルドキャッシュ | `docker compose build --no-cache frontend` |
| DB接続エラー（backend起動直後） | PostgreSQL初期化中 | healthcheck連鎖により自動で解決。待機すればOK |
| `failed to prepare extraction snapshot` | Docker Desktopキャッシュ破損 | `docker builder prune -f` 後に再ビルド |
| 編集ボタンクリック時にフリーズ | useEffect依存配列の問題 | 修正済み（依存を[log.id]のみに限定） |
| 類似ログに無関係なログが表示 | host_id fallbackバグ | 修正済み（条件なし時は空配列返却） |
| 対応内容欄の間隔が広い | flex:0 0 55pxが高さに適用 | 修正済み（.field-row.full labelにflex:none） |

### 10.2 ログ確認方法

```powershell
# 全コンテナのログ
docker compose logs

# 特定コンテナのログ（リアルタイム）
docker compose logs -f backend
docker compose logs -f db

# DB直接接続
docker compose exec db psql -U incilog -d incilog

# テーブル確認
docker compose exec db psql -U incilog -d incilog -c "\dt"

# ログ件数確認
docker compose exec db psql -U incilog -d incilog -c "SELECT COUNT(*) FROM logs;"
```

---

## 11. 今後の拡張計画

| フェーズ | 内容 | 技術 |
|----------|------|------|
| Phase 2 | Terraform によるAWSインフラ構成 | HCP Terraform |
| Phase 3 | GitHub Actions CI/CD パイプライン | GitHub Actions, Docker Hub |
| Phase 3 | セキュリティスキャン自動化 | Trivy, tfsec |
| Phase 4 | Kubernetes (EKS) へのデプロイ | EKS, Helm |
| 将来 | Prometheus + Grafana 監視連携 | Prometheus, Grafana |
| 将来 | 認証機能追加（OAuth2 / LDAP） | FastAPI Security |

---

## 付録A. .gitignore 推奨設定

```gitignore
# Python
__pycache__/
*.pyc
.venv/
*.egg-info/

# Node.js
node_modules/
frontend/node_modules/

# 環境変数
.env

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db

# Docker
*.log

# DB Volume（ローカルバインドマウント使用時）
pgdata/
```

---

## 付録B. 依存パッケージ一覧

### Backend (Python)

| パッケージ | バージョン | 用途 |
|-----------|-----------|------|
| fastapi | 0.115.6 | Webフレームワーク |
| uvicorn | 0.34.0 | ASGIサーバ |
| sqlalchemy | 2.0.36 | ORM |
| psycopg2-binary | 2.9.10 | PostgreSQLドライバ |
| pydantic | 2.10.3 | データバリデーション |
| openpyxl | 3.1.5 | Excelファイル生成 |

### Frontend (Node.js)

| パッケージ | 用途 |
|-----------|------|
| react | UIライブラリ |
| react-dom | DOMレンダリング |
| react-scripts | CRA開発ツール |
