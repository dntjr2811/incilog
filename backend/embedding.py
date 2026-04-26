"""
ログ埋め込みベクトル生成モジュール

multilingual-e5-large の ONNX モデルをローカルフォルダから直接ロードする。
外部ネットワーク（huggingface.co）への依存を排除し、社内環境でも安定動作する。

【ファイル配置】
  /app/models/multilingual-e5-large-onnx/
    ├── model.onnx
    ├── model.onnx_data
    ├── tokenizer.json
    ├── tokenizer_config.json
    ├── special_tokens_map.json
    ├── sentencepiece.bpe.model
    └── config.json

【重要】e5系モデルは入力に prefix が必要:
  - インデックス対象（保存）: "passage: " を先頭に付与
  - 検索クエリ:                "query: " を先頭に付与
"""
from __future__ import annotations

import logging
import os
import threading
from typing import List, Optional

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

logger = logging.getLogger(__name__)

# モデル名は識別用ラベル（ローカル運用のためダウンロードはしない）
EMBEDDING_MODEL_NAME = os.getenv("EMBEDDING_MODEL", "intfloat/multilingual-e5-large")
# ローカルモデルの配置先
EMBEDDING_MODEL_DIR = os.getenv("EMBEDDING_MODEL_DIR", "/app/models/multilingual-e5-large-onnx")
EMBEDDING_DIM = 1024  # multilingual-e5-large の出力次元

# 内部状態（シングルトン）
_session: Optional[ort.InferenceSession] = None
_tokenizer: Optional[Tokenizer] = None
_lock = threading.Lock()

MAX_LENGTH = 512  # e5-large のトークン上限


def _load():
    """ONNX セッションと tokenizer をロード。シングルトン。"""
    global _session, _tokenizer
    if _session is not None and _tokenizer is not None:
        return _session, _tokenizer

    with _lock:
        if _session is not None and _tokenizer is not None:
            return _session, _tokenizer

        model_path = os.path.join(EMBEDDING_MODEL_DIR, "model.onnx")
        tokenizer_path = os.path.join(EMBEDDING_MODEL_DIR, "tokenizer.json")

        if not os.path.exists(model_path):
            raise FileNotFoundError(
                f"ONNX model not found at {model_path}. "
                f"Make sure the model files are placed in {EMBEDDING_MODEL_DIR}."
            )
        if not os.path.exists(tokenizer_path):
            raise FileNotFoundError(
                f"tokenizer.json not found at {tokenizer_path}."
            )

        logger.info(f"Loading ONNX embedding model from: {EMBEDDING_MODEL_DIR}")
        sess_options = ort.SessionOptions()
        sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        _session = ort.InferenceSession(
            model_path,
            sess_options=sess_options,
            providers=["CPUExecutionProvider"],
        )
        _tokenizer = Tokenizer.from_file(tokenizer_path)
        # padding と truncation の設定
        _tokenizer.enable_padding(pad_id=1, pad_token="<pad>", length=None)
        _tokenizer.enable_truncation(max_length=MAX_LENGTH)
        logger.info("Embedding model loaded successfully")

        return _session, _tokenizer


def _mean_pool(last_hidden: np.ndarray, attention_mask: np.ndarray) -> np.ndarray:
    """Mean pooling — attention_mask を考慮した平均。"""
    mask = attention_mask[..., None].astype(np.float32)
    summed = (last_hidden * mask).sum(axis=1)
    counts = mask.sum(axis=1).clip(min=1e-9)
    return summed / counts


def _l2_normalize(vec: np.ndarray) -> np.ndarray:
    """L2正規化 — cosine類似度計算のため。"""
    norms = np.linalg.norm(vec, axis=1, keepdims=True).clip(min=1e-12)
    return vec / norms


def _encode_batch(texts: List[str]) -> np.ndarray:
    """テキストのバッチを埋め込みベクトルに変換する。"""
    session, tokenizer = _load()

    encodings = tokenizer.encode_batch(texts)
    input_ids = np.array([e.ids for e in encodings], dtype=np.int64)
    attention_mask = np.array([e.attention_mask for e in encodings], dtype=np.int64)

    input_names = {i.name for i in session.get_inputs()}
    feed = {"input_ids": input_ids, "attention_mask": attention_mask}
    if "token_type_ids" in input_names:
        feed["token_type_ids"] = np.zeros_like(input_ids)

    outputs = session.run(None, feed)
    last_hidden = outputs[0]  # [batch, seq, hidden]

    pooled = _mean_pool(last_hidden, attention_mask)
    normalized = _l2_normalize(pooled)
    return normalized


def build_source_text(hostname: Optional[str], message: str) -> str:
    """埋め込み入力テキストを構築する。

    設計判断: hostname は入力に含めない。
    理由:
      - host_id による1次フィルタで既にホスト絞込み済み
      - hostname を含めると同一ホスト内の全ログが共通プレフィックスを持ち、
        埋め込みベクトルが互いに近づきすぎる（ホスト識別が支配的になる）
      - 意味の解像度を上げるため、message のみを使用する。
    """
    return message


def encode_passage(text: str) -> List[float]:
    """インデックス用テキストの埋め込みを生成する（passage prefix付与）"""
    prefixed = f"passage: {text}"
    vectors = _encode_batch([prefixed])
    return vectors[0].tolist()


def encode_passages_batch(texts: List[str], batch_size: int = 32) -> List[List[float]]:
    """複数テキストの埋め込みを一括生成する（バックフィル/一括取込用）"""
    if not texts:
        return []
    prefixed = [f"passage: {t}" for t in texts]
    results: List[List[float]] = []
    for i in range(0, len(prefixed), batch_size):
        batch = prefixed[i : i + batch_size]
        vectors = _encode_batch(batch)
        results.extend(v.tolist() for v in vectors)
    return results


def encode_query(text: str) -> List[float]:
    """検索クエリ用テキストの埋め込みを生成する（query prefix付与）"""
    prefixed = f"query: {text}"
    vectors = _encode_batch([prefixed])
    return vectors[0].tolist()


def warmup() -> bool:
    """アプリケーション起動時にモデルを事前ロードする。"""
    try:
        _load()
        encode_passage("warmup")
        return True
    except Exception as e:
        logger.error(f"Embedding model warmup failed: {e}")
        return False
