-- ============================================
-- InciLog v2 — ベクトル検索拡張
-- pgvector extension + log_embeddings テーブル
-- ============================================
-- 既存DBへ適用する場合は以下を実行:
--   docker compose exec db psql -U incilog -d incilog -f /docker-entrypoint-initdb.d/03_vector_migration.sql
-- ============================================

-- pgvector extension の有効化
CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================
-- log_embeddings: ログの埋め込みベクトルを保持
-- ============================================
-- 設計意図:
--   logsテーブルにvectorカラムを追加せず別テーブルとした理由:
--   1. logsテーブルの肥大化を防止（vector(768)は約3KB/row）
--   2. モデル変更時にlogs本体を触らずに済む
--   3. 埋め込み生成失敗時もlogs本体は無損失
--   4. 将来的にモデル併用（A/Bテスト）する際もスキーマ変更不要
-- ============================================
CREATE TABLE IF NOT EXISTS log_embeddings (
    log_id      INTEGER PRIMARY KEY REFERENCES logs(id) ON DELETE CASCADE,
    embedding   vector(1024) NOT NULL,        -- multilingual-e5-large の出力次元
    model       VARCHAR(100) NOT NULL,        -- 生成モデル名（追跡用）
    source_text TEXT         NOT NULL,        -- 埋め込み入力テキスト（デバッグ用）
    created_at  TIMESTAMPTZ  DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  DEFAULT NOW()
);

-- HNSW インデックス（cosine距離）
-- HNSW は IVFFlat よりも recall が高く、データ追加に強い
-- m=16, ef_construction=64 はデータセット小〜中規模での標準的な値
CREATE INDEX IF NOT EXISTS idx_log_embeddings_hnsw
    ON log_embeddings
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- モデル別検索用（モデル併用時の絞込）
CREATE INDEX IF NOT EXISTS idx_log_embeddings_model
    ON log_embeddings(model);
