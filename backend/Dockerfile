FROM python:3.12-slim

WORKDIR /app

# 依存パッケージインストール（社内プロキシ対応: SSL検証スキップ）
COPY requirements.txt .
RUN pip install --no-cache-dir --trusted-host pypi.org --trusted-host files.pythonhosted.org -r requirements.txt

# curlをインストール（ヘルスチェック用、社内プロキシ対応）
RUN apt-get -o Acquire::https::Verify-Peer=false update \
    && apt-get -o Acquire::https::Verify-Peer=false install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# アプリケーションコピー
COPY . .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
