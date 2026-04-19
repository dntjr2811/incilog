-- ============================================
-- InciLog v2 — アラーム対応管理ツール
-- テーブル定義のみ（初期データなし）
-- ============================================

CREATE TABLE IF NOT EXISTS hosts (
    id          SERIAL PRIMARY KEY,
    hostname    VARCHAR(50) NOT NULL UNIQUE,
    description VARCHAR(200),
    category    VARCHAR(50),
    notes       TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS response_templates (
    id              SERIAL PRIMARY KEY,
    title           VARCHAR(200) NOT NULL,
    content         TEXT NOT NULL,
    team            VARCHAR(20),
    match_host      VARCHAR(50),
    match_code      VARCHAR(30),
    match_device    VARCHAR(50),
    match_keyword   VARCHAR(50),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS logs (
    id              SERIAL PRIMARY KEY,
    event_date      DATE NOT NULL,
    event_time      TIME NOT NULL,
    host_id         INTEGER REFERENCES hosts(id),
    message         TEXT NOT NULL,
    team            VARCHAR(20),
    response        TEXT,
    assignee        VARCHAR(200),
    reviewer        VARCHAR(200),
    status          VARCHAR(20) NOT NULL DEFAULT 'new'
                    CHECK (status IN ('new', 'responded', 'closed')),
    group_id        INTEGER,
    message_code    VARCHAR(30),
    jobnet_path     VARCHAR(200),
    org_name        VARCHAR(100),
    source_device   VARCHAR(50),
    interface_no    VARCHAR(20),
    event_keyword   VARCHAR(50),
    jobnet_name     VARCHAR(200),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_logs_host_id ON logs(host_id);
CREATE INDEX idx_logs_event_date ON logs(event_date);
CREATE INDEX idx_logs_status ON logs(status);
CREATE INDEX idx_logs_team ON logs(team);
CREATE INDEX idx_logs_message_code ON logs(message_code);
CREATE INDEX idx_logs_source_device ON logs(source_device);
CREATE INDEX idx_logs_event_keyword ON logs(event_keyword);
CREATE INDEX idx_logs_group_id ON logs(group_id);
CREATE INDEX idx_logs_jobnet_path ON logs(jobnet_path);