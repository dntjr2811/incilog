"""
既存ログの埋め込みベクトル バックフィルスクリプト

実行方法:
    docker compose exec backend python -m scripts.backfill

対象:
    log_embeddings テーブルに未登録の logs レコード全件

特徴:
    - バッチ単位で埋め込み生成（CPU効率向上）
    - 失敗してもトランザクション分離（1バッチ失敗で全停止しない）
    - 進捗表示
"""
from __future__ import annotations

import sys
from datetime import datetime

# main.py と同階層から実行されるためパス調整
sys.path.insert(0, "/app")

from sqlalchemy import select, and_  # noqa: E402
from main import SessionLocal, Log, LogEmbedding  # noqa: E402
import embedding  # noqa: E402

BATCH_SIZE = 32


def backfill():
    db = SessionLocal()
    try:
        # 埋め込み未生成のログを抽出（LEFT JOIN + IS NULL）
        sql = (
            select(Log)
            .outerjoin(LogEmbedding, LogEmbedding.log_id == Log.id)
            .where(LogEmbedding.log_id.is_(None))
            .order_by(Log.id)
        )
        logs_to_process = db.execute(sql).scalars().all()
        total = len(logs_to_process)

        print(f"[{datetime.now().isoformat(timespec='seconds')}] "
              f"バックフィル対象: {total}件 / モデル: {embedding.EMBEDDING_MODEL_NAME}")

        if total == 0:
            print("処理対象なし。終了します。")
            return

        # モデル事前ロード
        embedding.warmup()

        success = 0
        failed = 0
        for i in range(0, total, BATCH_SIZE):
            batch = logs_to_process[i : i + BATCH_SIZE]
            texts = [
                embedding.build_source_text(
                    log.host.hostname if log.host else None,
                    log.message,
                )
                for log in batch
            ]

            try:
                vectors = embedding.encode_passages_batch(texts, batch_size=BATCH_SIZE)
            except Exception as e:
                print(f"  [ERR] バッチ {i}〜{i+len(batch)-1} で埋め込み生成失敗: {e}")
                failed += len(batch)
                continue

            # 個別レコードのINSERT/UPDATE
            for log, src_text, vec in zip(batch, texts, vectors):
                try:
                    emb = LogEmbedding(
                        log_id=log.id,
                        embedding=vec,
                        model=embedding.EMBEDDING_MODEL_NAME,
                        source_text=src_text,
                    )
                    db.merge(emb)
                    success += 1
                except Exception as e:
                    print(f"  [ERR] log_id={log.id} の保存失敗: {e}")
                    failed += 1

            db.commit()
            done = min(i + BATCH_SIZE, total)
            print(f"  進捗: {done}/{total}  (success={success}, failed={failed})")

        print(f"[{datetime.now().isoformat(timespec='seconds')}] "
              f"バックフィル完了 — success={success}, failed={failed}")

    finally:
        db.close()


if __name__ == "__main__":
    backfill()
