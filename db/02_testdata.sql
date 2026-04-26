-- ============================================
-- InciLog テストデータ v2（汎用インフラ監視）
-- 設計方針:
--   ベクトル類似度検索の有効性を検証可能にするため、
--   各ホストに同種アラームを複数件配置し、host_idフィルタ後でも
--   意味的に近いログのペアが残るようにする。
--
--   さらに「同じ事象を異なる文言で表現したログ」を意図的に混ぜ、
--   キーワード一致では拾えない意味検索の強みを検証可能にする。
-- ============================================

-- ホストマスタ
INSERT INTO hosts (hostname, description, category) VALUES
  ('WEB-PROD-01',  '本番Webサーバ1 (nginx)',          'Web'),
  ('WEB-PROD-02',  '本番Webサーバ2 (nginx)',          'Web'),
  ('AP-PROD-01',   '本番APサーバ1 (Tomcat)',          'AP'),
  ('AP-PROD-02',   '本番APサーバ2 (Tomcat)',          'AP'),
  ('DB-PROD-01',   '本番DBサーバ (PostgreSQL Primary)','DB'),
  ('DB-PROD-02',   '本番DBサーバ (PostgreSQL Replica)','DB'),
  ('BATCH-01',     'バッチ処理サーバ',                  'Batch'),
  ('MON-01',       '統合監視サーバ (Zabbix)',          '監視'),
  ('NW-CORE-01',   'コアスイッチ (Catalyst)',           'NW'),
  ('NW-DIST-01',   'ディストリビューションSW',          'NW'),
  ('FW-01',        'ファイアウォール (FortiGate)',      'NW'),
  ('LB-01',        'ロードバランサ (F5 BIG-IP)',       'NW'),
  ('MAIL-01',      'メールサーバ (Postfix)',           'Mail'),
  ('FILE-01',      'ファイルサーバ (Samba)',            'Storage'),
  ('BK-01',        'バックアップサーバ (Veeam)',        'Backup'),
  ('VM-HOST-01',   '仮想基盤ホスト1 (ESXi)',           'VM'),
  ('VM-HOST-02',   '仮想基盤ホスト2 (ESXi)',           'VM'),
  ('DNS-01',       'DNSサーバ (BIND)',                 'Infra'),
  ('NTP-01',       'NTPサーバ',                        'Infra'),
  ('PROXY-01',     'プロキシサーバ (Squid)',            'Infra');

-- 対応テンプレート
INSERT INTO response_templates (title, content, team, match_keyword) VALUES
  ('ディスク使用率アラート',       E'ディスク使用率が閾値を超過。\n不要ファイルの削除またはディスク拡張を検討。',         '運用T', 'disk_usage'),
  ('CPU高負荷',                   E'CPU使用率が閾値を超過。\nプロセス確認(top/htop)で原因特定。負荷が継続する場合はスケールアップを検討。', '運用T', 'cpu_high'),
  ('メモリ不足',                  E'メモリ使用率が閾値を超過。\nOOM Killerが動作する前にプロセスの再起動またはメモリ増設を検討。',       '運用T', 'memory_high'),
  ('NW linkDown',                 E'ポートのリンクダウンを検知。\n対向機器の状態とケーブルを確認。計画作業による場合は静観。',           '運用T', 'linkDown'),
  ('NW linkUp',                   'ポートのリンクアップを確認。linkDown復旧。正常動作を確認し完了。',                                   '運用T', 'linkUp'),
  ('サービス停止',                E'サービスの停止を検知。\nsystemctl status で状態確認 → restart で復旧試行。',                       '運用T', 'service_down'),
  ('SSL証明書期限',               E'SSL証明書の有効期限が近づいています。\n更新手順に従い証明書を更新してください。',                    '運用T', 'ssl_expire'),
  ('バックアップ失敗',            E'バックアップジョブが失敗しました。\nログを確認し、ディスク容量・ネットワーク接続を確認してください。', '運用T', 'backup_fail'),
  ('ログイン失敗',                '認証失敗を検知。正規ユーザの入力ミスか不正アクセスか確認。連続発生時はアカウントロック状況を確認。',  'セキュリティT', 'auth_fail'),
  ('VMware HA イベント',          E'仮想マシンのHA再起動を検知。\nホストの障害状況を確認。vCLSの再起動であれば静観。',                  '運用T', 'vm_ha');

INSERT INTO response_templates (title, content, team, match_code) VALUES
  ('Zabbixトリガー復旧',          '監視トリガーが自動復旧しました。一時的な負荷による発報と判断し静観。',                              '運用T', 'RESOLVED'),
  ('バッチジョブ異常終了',        E'バッチジョブが異常終了しました。\nジョブログを確認し、リカバリ手順に従い再実行してください。',        '開発T',     'JOB_FAIL');

-- ============================================
-- ログデータ 100件
-- 設計: 各ホストに同種アラーム複数件 + 同事象の表現バリエーション
-- ============================================

-- ============================================
-- WEB-PROD-01: ディスク多発 + nginx関連 (10件)
-- 検証: 同一ホスト内のディスクアラート同士、サービス停止同士が高類似度になるか
-- ============================================
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-01','09:15:22',(SELECT id FROM hosts WHERE hostname='WEB-PROD-01'),
  'WARNING: Disk usage on /var/log reached 92%. Threshold: 90%',
  '運用T','不要ログファイルを削除し85%に低下。logrotate設定を見直し。','山田','鈴木','closed','disk_usage'),
('2026-03-03','11:20:15',(SELECT id FROM hosts WHERE hostname='WEB-PROD-01'),
  '/var/log の空き容量が逼迫しています (使用率93%)。アクセスログが急増。',
  '運用T','アクセスログのローテーション周期を見直し。圧縮設定を有効化。','鈴木','山田','closed','disk_usage'),
('2026-03-05','14:30:11',(SELECT id FROM hosts WHERE hostname='WEB-PROD-01'),
  'WARNING: Filesystem /var/log is 89% full. Old logs need cleanup.',
  '運用T','古いログファイルを外部ストレージへ移動。','山田','鈴木','closed','disk_usage'),
('2026-03-08','03:22:45',(SELECT id FROM hosts WHERE hostname='WEB-PROD-01'),
  'CRITICAL: /var partition usage 95%. Service may stop.',
  '運用T','緊急対応。/var/cache/nginx の古いキャッシュを削除し空き確保。','山田','佐藤','closed','disk_usage'),
('2026-03-10','06:30:12',(SELECT id FROM hosts WHERE hostname='WEB-PROD-01'),
  'Service nginx is not running. systemctl status: inactive (dead)',
  '運用T','OOM Killerによりnginxプロセスが停止。メモリ増設後にsystemctl restart nginxで復旧。','山田','鈴木','closed','service_down'),
('2026-03-15','22:45:33',(SELECT id FROM hosts WHERE hostname='WEB-PROD-01'),
  'nginx プロセスが応答していません。ヘルスチェック失敗。',
  '運用T','設定リロード時の構文エラー。nginx -t で確認後、設定修正して再起動。','鈴木','田中','closed','service_down'),
('2026-03-18','16:10:27',(SELECT id FROM hosts WHERE hostname='WEB-PROD-01'),
  'WARNING: Memory usage reached 92%. Available: 800MB / 8192MB',
  '運用T','nginxワーカープロセス数を調整。worker_connections設定を最適化。','鈴木','佐藤','closed','memory_high'),
('2026-04-01','08:20:14',(SELECT id FROM hosts WHERE hostname='WEB-PROD-01'),
  'WARNING: Disk usage on /var/log reached 91%. Threshold: 90%',
  '運用T',NULL,'山田',NULL,'new','disk_usage'),
('2026-04-10','16:45:22',(SELECT id FROM hosts WHERE hostname='WEB-PROD-01'),
  'WARNING: SSL certificate for www.example.com expires in 14 days',
  '運用T','証明書更新手続きを開始。Let''s Encryptで自動更新設定済みだが手動確認。','鈴木','山田','responded','ssl_expire'),
('2026-04-14','03:30:55',(SELECT id FROM hosts WHERE hostname='WEB-PROD-01'),
  'nginxサービスが停止しています。プロセスが見つかりません。',
  '運用T',NULL,NULL,NULL,'new','service_down');

-- ============================================
-- DB-PROD-01: PostgreSQL リソース系 (10件)
-- 検証: CPU/Memory/Disk が混在する中で意味的に近いものが正しく分類されるか
-- ============================================
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-02','14:30:11',(SELECT id FROM hosts WHERE hostname='DB-PROD-01'),
  'CRITICAL: Disk usage on /var/lib/postgresql reached 95%. Threshold: 90%',
  '運用T','古いWALファイルをアーカイブ後削除。pg_repackでテーブル圧縮実施。','佐藤','山田','closed','disk_usage'),
('2026-03-04','08:15:22',(SELECT id FROM hosts WHERE hostname='DB-PROD-01'),
  'WAL領域の使用率が90%を超過しました。アーカイブが追いついていません。',
  '運用T','archive_command の見直し。古いアーカイブをS3に退避。','佐藤','鈴木','closed','disk_usage'),
('2026-03-07','02:15:33',(SELECT id FROM hosts WHERE hostname='DB-PROD-01'),
  'CRITICAL: CPU usage reached 95% for 3 minutes. Top process: postgres (PID 34567)',
  '運用T','pg_stat_activityで長時間クエリ発見。EXPLAIN結果からインデックス追加で解決。','佐藤','鈴木','closed','cpu_high'),
('2026-03-11','10:45:18',(SELECT id FROM hosts WHERE hostname='DB-PROD-01'),
  'PostgreSQLのCPU負荷が高い状態が継続しています (90%以上、5分間)',
  '運用T','autovacuum の停止プロセスが原因。手動でVACUUM ANALYZE実行後に正常化。','佐藤','山田','closed','cpu_high'),
('2026-03-14','19:22:44',(SELECT id FROM hosts WHERE hostname='DB-PROD-01'),
  'CPU使用率が98%に達しました。長時間実行クエリの可能性があります。',
  '運用T','pg_terminate_backendで該当クエリ強制終了。アプリケーション側でタイムアウト設定追加。','佐藤','鈴木','closed','cpu_high'),
('2026-03-19','08:55:31',(SELECT id FROM hosts WHERE hostname='DB-PROD-01'),
  'WARNING: Memory usage reached 88%. shared_buffers consuming 4GB',
  '運用T','shared_buffersの設定値が適正範囲内であることを確認。一時的なキャッシュ増加のため静観。','佐藤','山田','closed','memory_high'),
('2026-03-23','13:10:55',(SELECT id FROM hosts WHERE hostname='DB-PROD-01'),
  'PostgreSQL のメモリ使用量が過大 (90%超過)。スワップ発生中。',
  '運用T','work_mem の設定が大きすぎる接続を特定。コネクションプールで制限。','佐藤','鈴木','closed','memory_high'),
('2026-03-28','15:40:22',(SELECT id FROM hosts WHERE hostname='DB-PROD-01'),
  'PostgreSQL: FATAL: too many connections for role "app_user"',
  '運用T','コネクションプール設定不備。pgbouncerの最大接続数を調整。','佐藤','山田','closed','service_down'),
('2026-04-05','10:15:30',(SELECT id FROM hosts WHERE hostname='DB-PROD-01'),
  'WARNING: Disk usage on /var/lib/postgresql reached 88%.',
  '運用T','レプリケーション遅延なし。Primaryと同様にWALクリーンアップ実施。','佐藤','鈴木','responded','disk_usage'),
('2026-04-12','11:30:22',(SELECT id FROM hosts WHERE hostname='DB-PROD-01'),
  'postgres プロセスのCPU消費が継続的に高い (92%)',
  '運用T',NULL,NULL,NULL,'new','cpu_high');

-- ============================================
-- AP-PROD-01: Tomcat 高負荷とOOM (10件)
-- 検証: Java/Tomcat 関連の表現バリエーション同士の類似度
-- ============================================
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-02','10:30:45',(SELECT id FROM hosts WHERE hostname='AP-PROD-01'),
  'CRITICAL: CPU usage reached 98% for 5 minutes. Top process: java (PID 12345)',
  '運用T','Tomcatのスレッドプール枯渇。maxThreads=200→300に変更し再起動。','山田','鈴木','closed','cpu_high'),
('2026-03-05','13:22:18',(SELECT id FROM hosts WHERE hostname='AP-PROD-01'),
  'Tomcatプロセスが高CPU状態。スレッドダンプ取得を推奨。',
  '運用T','jstack でスレッドダンプ取得。デッドロック検出。アプリチームに調査依頼。','山田','佐藤','closed','cpu_high'),
('2026-03-09','12:45:33',(SELECT id FROM hosts WHERE hostname='AP-PROD-01'),
  'Service tomcat is not running. systemctl status: failed',
  '運用T','catalina.outにOutOfMemoryError確認。ヒープ設定見直し後に再起動。','佐藤','山田','closed','service_down'),
('2026-03-13','09:15:22',(SELECT id FROM hosts WHERE hostname='AP-PROD-01'),
  'Tomcat が応答しません。java プロセスは存在しますがリクエストを処理していません。',
  '運用T','GCログ確認。Full GC連続発生でスタック。ヒープ拡張(4G→8G)で復旧。','山田','鈴木','closed','service_down'),
('2026-03-17','11:30:44',(SELECT id FROM hosts WHERE hostname='AP-PROD-01'),
  'CRITICAL: Memory usage reached 96%. OOM Killer may activate. Available: 512MB / 16384MB',
  '運用T','Javaヒープダンプ取得。メモリリーク箇所を特定しアプリチームに報告。暫定でTomcat再起動。','山田','鈴木','closed','memory_high'),
('2026-03-21','14:20:18',(SELECT id FROM hosts WHERE hostname='AP-PROD-01'),
  'java プロセスのメモリ使用量がヒープ上限に到達 (Old領域95%)',
  '運用T','GCチューニング実施。-XX:+UseG1GC に切替で改善。','山田','佐藤','closed','memory_high'),
('2026-03-24','09:10:18',(SELECT id FROM hosts WHERE hostname='AP-PROD-01'),
  'sshd: Failed password for root from 10.0.0.50 port 43210 ssh2. 5 consecutive failures.',
  'セキュリティT','内部サーバからのrootログイン試行。運用者の作業ミス。root SSHログイン禁止設定を再確認。','山田','鈴木','closed','auth_fail'),
('2026-03-27','16:30:55',(SELECT id FROM hosts WHERE hostname='AP-PROD-01'),
  'Tomcat OutOfMemoryError: Java heap space',
  '運用T','ヒープダンプ解析でメモリリーク確認。アプリ修正版デプロイ。暫定対応でヒープサイズ拡張。','山田','佐藤','closed','memory_high'),
('2026-04-01','08:20:14',(SELECT id FROM hosts WHERE hostname='AP-PROD-01'),
  'WARNING: Disk usage on /opt/tomcat/logs reached 91%. Threshold: 90%',
  '運用T',NULL,'山田',NULL,'new','disk_usage'),
('2026-04-13','13:45:22',(SELECT id FROM hosts WHERE hostname='AP-PROD-01'),
  'java プロセスのCPU使用率が99%継続。Full GC実行中の可能性。',
  '運用T',NULL,NULL,NULL,'new','cpu_high');

-- ============================================
-- BATCH-01: バッチジョブ失敗パターン (10件)
-- 検証: 同種ジョブ失敗（DB接続/ディスク/ファイル不在）が分類できるか
-- ============================================
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, message_code, event_keyword) VALUES
('2026-03-01','02:30:10',(SELECT id FROM hosts WHERE hostname='BATCH-01'),
  'JOB_FAIL: Daily backup job [daily_db_backup] failed. Exit code: 1. Error: Connection refused to DB-PROD-01:5432',
  '開発T','DBサーバのメンテナンスウィンドウと重複。スケジュール変更後に再実行し正常終了。','佐藤','山田','closed','JOB_FAIL','backup_fail'),
('2026-03-04','03:15:22',(SELECT id FROM hosts WHERE hostname='BATCH-01'),
  'バックアップジョブがDB接続エラーで異常終了 (host=DB-PROD-01 port=5432 connection refused)',
  '開発T','ネットワーク経路上のFW設定変更が原因。ルール修正で復旧。','田中','佐藤','closed','JOB_FAIL','backup_fail'),
('2026-03-08','01:05:44',(SELECT id FROM hosts WHERE hostname='BATCH-01'),
  'JOB_FAIL: Data export job [csv_export] failed. Exit code: 1. Error: Disk full on /data/export',
  '開発T','エクスポート先ディスク容量不足。古いファイル削除後に再実行。','田中','山田','closed','JOB_FAIL','disk_usage'),
('2026-03-11','04:30:18',(SELECT id FROM hosts WHERE hostname='BATCH-01'),
  'JOB_FAIL: Daily ETL job [etl_daily] failed. Exit code: 3. Error: Source file not found: /data/input/daily_20260311.csv',
  '開発T','外部システムからのファイル連携遅延。連携先に確認後、ファイル到着を待って再実行。','佐藤','田中','closed','JOB_FAIL',NULL),
('2026-03-15','05:20:33',(SELECT id FROM hosts WHERE hostname='BATCH-01'),
  'ETL処理が入力ファイル未検出により失敗 (path=/data/input/)',
  '開発T','送信元バッチサーバの停止が原因。再送依頼後に再実行。','田中','佐藤','closed','JOB_FAIL',NULL),
('2026-03-19','02:45:11',(SELECT id FROM hosts WHERE hostname='BATCH-01'),
  'JOB_FAIL: Daily backup job [daily_db_backup] failed. Exit code: 1. Error: pg_dump timeout after 3600 seconds',
  '開発T','大量データ更新後のバックアップ時間超過。pg_dumpのタイムアウトを7200秒に延長。','佐藤','山田','closed','JOB_FAIL','backup_fail'),
('2026-03-22','06:10:27',(SELECT id FROM hosts WHERE hostname='BATCH-01'),
  'CSVエクスポートジョブがディスク容量不足で失敗',
  '開発T','エクスポート先ボリュームを20GB増設。','山田','佐藤','closed','JOB_FAIL','disk_usage'),
('2026-03-25','03:30:55',(SELECT id FROM hosts WHERE hostname='BATCH-01'),
  'RESOLVED: Daily backup job [daily_db_backup] completed successfully. Duration: 2h15m',
  '開発T','前回失敗分の正常完了確認。','佐藤','山田','closed','RESOLVED','backup_fail'),
('2026-04-04','02:30:22',(SELECT id FROM hosts WHERE hostname='BATCH-01'),
  'JOB_FAIL: Daily backup job [daily_db_backup] failed. Exit code: 1. Error: Connection refused to DB-PROD-01:5432',
  '開発T',NULL,'佐藤',NULL,'new','JOB_FAIL','backup_fail'),
('2026-04-13','02:55:44',(SELECT id FROM hosts WHERE hostname='BATCH-01'),
  'JOB_FAIL: Data export job [csv_export] failed. Exit code: 1. Error: Disk full on /data/export',
  '開発T',NULL,NULL,NULL,'new','JOB_FAIL','disk_usage');

-- ============================================
-- NW-CORE-01: linkDown/Up ペア多数 (8件)
-- 検証: 異なるインターフェイスの linkDown 同士が高類似度になるか
-- ============================================
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, source_device, interface_no, event_keyword) VALUES
('2026-03-01','14:22:10',(SELECT id FROM hosts WHERE hostname='NW-CORE-01'),
  'SNMP Trap: Interface GigabitEthernet0/1 link down (ifIndex: 10101)',
  '運用T','対向サーバWEB-PROD-01のNIC再起動による一時的な切断。5秒後にlinkUp確認。','鈴木','山田','closed','NW-CORE-01','10101','linkDown'),
('2026-03-01','14:22:15',(SELECT id FROM hosts WHERE hostname='NW-CORE-01'),
  'SNMP Trap: Interface GigabitEthernet0/1 link up (ifIndex: 10101)',
  '運用T','linkDown復旧確認。通信影響なし。','鈴木','山田','closed','NW-CORE-01','10101','linkUp'),
('2026-03-08','22:30:45',(SELECT id FROM hosts WHERE hostname='NW-CORE-01'),
  'ポート Gi0/3 がダウンしました',
  '運用T','対向機器の電源断。計画作業のため静観。','田中','鈴木','closed','NW-CORE-01','10103','linkDown'),
('2026-03-08','23:45:12',(SELECT id FROM hosts WHERE hostname='NW-CORE-01'),
  'ポート Gi0/3 がアップしました',
  '運用T','メンテナンス完了。linkUp確認。','田中','鈴木','closed','NW-CORE-01','10103','linkUp'),
('2026-03-16','03:45:08',(SELECT id FROM hosts WHERE hostname='NW-CORE-01'),
  'SNMP Trap: Interface TenGigabitEthernet1/1 link down (ifIndex: 20101)',
  '運用T','10G上位回線の瞬断。ISP側の機器交換作業によるもの。事前連絡あり。','山田','鈴木','closed','NW-CORE-01','20101','linkDown'),
('2026-03-16','03:45:35',(SELECT id FROM hosts WHERE hostname='NW-CORE-01'),
  'SNMP Trap: Interface TenGigabitEthernet1/1 link up (ifIndex: 20101)',
  '運用T','上位回線復旧。パケットロスなし確認。','山田','鈴木','closed','NW-CORE-01','20101','linkUp'),
('2026-03-28','19:10:33',(SELECT id FROM hosts WHERE hostname='NW-CORE-01'),
  'SNMP Trap: Interface GigabitEthernet0/5 link down (ifIndex: 10105)',
  '運用T','FILE-01のNICフラッピング。ケーブル交換で解消。','山田','佐藤','closed','NW-CORE-01','10105','linkDown'),
('2026-03-28','19:15:22',(SELECT id FROM hosts WHERE hostname='NW-CORE-01'),
  'SNMP Trap: Interface GigabitEthernet0/5 link up (ifIndex: 10105)',
  '運用T','ケーブル交換後linkUp安定。','山田','佐藤','closed','NW-CORE-01','10105','linkUp');

-- ============================================
-- FW-01: ファイアウォール / セキュリティ (8件)
-- 検証: 攻撃検知ログ同士の類似度
-- ============================================
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-11','08:15:33',(SELECT id FROM hosts WHERE hostname='FW-01'),
  'SNMP Trap: Interface port10 link down (ifIndex: 10)',
  '運用T','DMZセグメントのサーバ停止作業に伴うlinkDown。予定作業。','鈴木','佐藤','closed','linkDown'),
('2026-03-11','10:30:22',(SELECT id FROM hosts WHERE hostname='FW-01'),
  'SNMP Trap: Interface port10 link up (ifIndex: 10)',
  '運用T','DMZサーバ起動完了。通信復旧確認。','鈴木','佐藤','closed','linkUp'),
('2026-03-14','23:45:11',(SELECT id FROM hosts WHERE hostname='FW-01'),
  'FortiGate: Intrusion detected. Signature: HTTP.URI.SQL.Injection. Source: 203.0.113.50 Action: Blocked',
  'セキュリティT','WAF/IPSによる自動ブロック。送信元IPを調査しブラックリストに追加。','鈴木','佐藤','closed',NULL),
('2026-03-19','16:30:44',(SELECT id FROM hosts WHERE hostname='FW-01'),
  'FortiGate: Brute force attack detected. Source: 198.51.100.25 Target: 443/tcp Attempts: 150',
  'セキュリティT','外部からのブルートフォース攻撃。送信元IPをブロック。fail2banの閾値を調整。','鈴木','山田','closed','auth_fail'),
('2026-03-26','14:20:18',(SELECT id FROM hosts WHERE hostname='FW-01'),
  '不正アクセス検知: SQLインジェクション攻撃を遮断 (送信元 203.0.113.78)',
  'セキュリティT','攻撃元IPをジオブロック対象に追加。Webアプリ側のWAFルール強化。','鈴木','田中','closed',NULL),
('2026-04-06','22:15:11',(SELECT id FROM hosts WHERE hostname='FW-01'),
  'FortiGate: Brute force attack detected. Source: 192.0.2.80 Target: 22/tcp Attempts: 200',
  'セキュリティT',NULL,'鈴木',NULL,'new','auth_fail'),
('2026-04-07','21:30:44',(SELECT id FROM hosts WHERE hostname='FW-01'),
  'SNMP Trap: Interface port3 link down (ifIndex: 3)',
  '運用T','内部セグメント側ポート。対向SW再起動による瞬断。すぐ復旧。','鈴木','山田','responded','linkDown'),
('2026-04-11','05:30:22',(SELECT id FROM hosts WHERE hostname='FW-01'),
  '大量のSSH認証失敗を検知 (送信元 198.51.100.45 試行回数 180)',
  'セキュリティT',NULL,NULL,NULL,'new','auth_fail');

-- ============================================
-- BK-01: バックアップ系 (8件)
-- 検証: バックアップ失敗の様々な原因が意味的に分類できるか
-- ============================================
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-05','05:30:22',(SELECT id FROM hosts WHERE hostname='BK-01'),
  'Veeam: Backup job [VM-Daily-Backup] completed with warnings. 2 VMs skipped due to snapshot consolidation needed.',
  '運用T','スナップショット統合が必要なVMを特定。手動で統合実施後、翌日のバックアップで正常完了。','佐藤','山田','closed','backup_fail'),
('2026-03-12','04:45:18',(SELECT id FROM hosts WHERE hostname='BK-01'),
  'Veeam: Backup job [DB-Full-Backup] failed. Error: Insufficient free disk space on backup repository.',
  '運用T','バックアップリポジトリの容量不足。古い世代のバックアップを削除し再実行。','佐藤','鈴木','closed','backup_fail'),
('2026-03-15','22:10:08',(SELECT id FROM hosts WHERE hostname='BK-01'),
  'WARNING: Disk usage on /backup reached 91%. Threshold: 90%',
  '運用T','30日以上前のバックアップを外部ストレージに退避。','佐藤','田中','closed','disk_usage'),
('2026-03-18','06:30:33',(SELECT id FROM hosts WHERE hostname='BK-01'),
  'Veeam バックアップが容量不足で異常終了 (リポジトリ残容量 50GB)',
  '運用T','重複排除設定を有効化。古い世代を圧縮アーカイブ。','佐藤','田中','closed','backup_fail'),
('2026-03-26','06:00:44',(SELECT id FROM hosts WHERE hostname='BK-01'),
  'Veeam: Backup job [File-Server-Backup] failed. Error: Network path not found \\FILE-01\share',
  '運用T','ファイルサーバのSambaサービス再起動でネットワークパス復旧。バックアップ再実行で正常終了。','佐藤','田中','closed','backup_fail'),
('2026-04-02','05:30:11',(SELECT id FROM hosts WHERE hostname='BK-01'),
  'Veeam: Backup job [VM-Daily-Backup] failed. Error: Cannot create snapshot for VM [DB-PROD-01].',
  '運用T',NULL,'佐藤',NULL,'new','backup_fail'),
('2026-04-09','04:15:22',(SELECT id FROM hosts WHERE hostname='BK-01'),
  'Veeam: Backup job [DB-Full-Backup] completed with errors. 1 database backup truncated.',
  '運用T',NULL,NULL,NULL,'new','backup_fail'),
('2026-04-11','01:20:33',(SELECT id FROM hosts WHERE hostname='BK-01'),
  'バックアップリポジトリの空き容量が不足 (残3%)',
  '運用T',NULL,'佐藤',NULL,'new','backup_fail');

-- ============================================
-- VM-HOST-01: 仮想基盤 (6件)
-- ============================================
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, source_device, event_keyword) VALUES
('2026-03-02','19:30:22',(SELECT id FROM hosts WHERE hostname='VM-HOST-01'),
  'VMware vCenter: Virtual machine [vCLS-01] has been powered off (vmwVmPoweredOff)',
  '運用T','vCLS（vSphere Cluster Service）の自動再起動。正常動作のため静観。','山田','鈴木','closed','VM-HOST-01','vm_ha'),
('2026-03-02','19:30:45',(SELECT id FROM hosts WHERE hostname='VM-HOST-01'),
  'VMware vCenter: Virtual machine [vCLS-01] has been powered on (vmwVmPoweredOn)',
  '運用T','vCLS再起動完了。正常動作確認。','山田','鈴木','closed','VM-HOST-01','vm_ha'),
('2026-03-18','03:05:44',(SELECT id FROM hosts WHERE hostname='VM-HOST-01'),
  'VMware vCenter: Host [VM-HOST-01] memory usage reached 92%. DRS may trigger vMotion.',
  '運用T','テスト環境VMの一時的なメモリ消費。テスト完了後に正常化。','山田','佐藤','closed','VM-HOST-01','memory_high'),
('2026-04-02','22:10:15',(SELECT id FROM hosts WHERE hostname='VM-HOST-01'),
  'VMware vCenter: Virtual machine [DB-PROD-02] has been powered off unexpectedly (vmwVmPoweredOff)',
  '運用T','ESXiホストのハードウェア障害によるVM停止。HAにより別ホストで自動起動確認。','佐藤','鈴木','closed','VM-HOST-01','vm_ha'),
('2026-04-08','14:25:33',(SELECT id FROM hosts WHERE hostname='VM-HOST-01'),
  'VMware vCenter: Datastore [DS-PROD-01] usage reached 90%. Threshold: 85%',
  '運用T',NULL,'山田',NULL,'new','VM-HOST-01','disk_usage'),
('2026-04-12','10:15:22',(SELECT id FROM hosts WHERE hostname='VM-HOST-01'),
  'ESXiホストのメモリ使用率が95%に達しました。vMotionが発生する可能性があります。',
  '運用T',NULL,NULL,NULL,'new','VM-HOST-01','memory_high');

-- ============================================
-- MAIL-01: メールサーバ (6件)
-- ============================================
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-17','04:10:55',(SELECT id FROM hosts WHERE hostname='MAIL-01'),
  'Service postfix is not running. systemctl status: failed',
  '運用T','メールキュー破損。postsuper -dで不正キュー削除後にsystemctl restart postfix。','田中','山田','closed','service_down'),
('2026-03-20','07:45:19',(SELECT id FROM hosts WHERE hostname='MAIL-01'),
  'WARNING: Disk usage on /var/spool/mail reached 89%. Threshold: 85%',
  '運用T','長期未読メールボックスをアーカイブ。メールボックスサイズ制限を設定。','田中','山田','closed','disk_usage'),
('2026-03-30','14:55:33',(SELECT id FROM hosts WHERE hostname='MAIL-01'),
  'postfix/smtpd: warning: unknown[203.0.113.100]: SASL LOGIN authentication failed',
  'セキュリティT','外部からのSMTPリレー試行。SMTPリレー制限が正常に機能していることを確認。','田中','鈴木','closed','auth_fail'),
('2026-04-08','11:45:22',(SELECT id FROM hosts WHERE hostname='MAIL-01'),
  'WARNING: Memory usage reached 85%. postfix queue growing',
  '運用T','メールキュー滞留。スパムフィルタの一時的な負荷増。キュー処理後に正常化。','田中','佐藤','responded','memory_high'),
('2026-04-12','08:30:15',(SELECT id FROM hosts WHERE hostname='MAIL-01'),
  'WARNING: SSL certificate for mail.example.com expires in 7 days',
  '運用T',NULL,NULL,NULL,'new','ssl_expire'),
('2026-04-14','12:20:33',(SELECT id FROM hosts WHERE hostname='MAIL-01'),
  'postfixサービスが応答していません。メールキューが処理されていません。',
  '運用T',NULL,NULL,NULL,'new','service_down');

-- ============================================
-- MON-01: 監視サーバ (5件)
-- ============================================
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-20','22:30:18',(SELECT id FROM hosts WHERE hostname='MON-01'),
  'Zabbix: Trigger fired: "Zabbix server performance is low" (Value: 45% busy)',
  '運用T','監視対象ホスト数増加に伴うZabbixサーバ負荷増。ハウスキーパー設定を最適化。','山田','佐藤','closed','cpu_high'),
('2026-03-27','08:55:11',(SELECT id FROM hosts WHERE hostname='MON-01'),
  'Zabbix: More than 100 items having missing data for more than 10 minutes',
  '運用T','一時的なネットワーク輻輳によるデータ取得遅延。自然回復。','山田','田中','closed',NULL),
('2026-04-10','15:45:22',(SELECT id FROM hosts WHERE hostname='MON-01'),
  'WARNING: Disk usage on /var/lib/zabbix reached 93%. Threshold: 90%',
  '運用T',NULL,NULL,NULL,'new','disk_usage'),
('2026-04-12','03:10:55',(SELECT id FROM hosts WHERE hostname='MON-01'),
  'WARNING: CPU usage reached 88% for 10 minutes. Zabbix server process',
  '運用T',NULL,NULL,NULL,'new','cpu_high'),
('2026-04-14','06:45:44',(SELECT id FROM hosts WHERE hostname='MON-01'),
  'Zabbix エージェントが応答していません (WEB-PROD-01 5分間)',
  '運用T',NULL,NULL,NULL,'new','service_down');

-- ============================================
-- 残りのホスト：少量ずつ配置 (合計19件で総計100件達成)
-- ============================================

-- WEB-PROD-02 (3件)
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-25','16:30:55',(SELECT id FROM hosts WHERE hostname='WEB-PROD-02'),
  'WARNING: Disk usage on /var/log reached 87%. Threshold: 85%',
  '運用T','アクセスログのローテーション周期を7日→3日に短縮。','鈴木','佐藤','closed','disk_usage'),
('2026-04-02','14:20:38',(SELECT id FROM hosts WHERE hostname='WEB-PROD-02'),
  'WARNING: Memory usage reached 90%. Available: 1024MB / 8192MB',
  '運用T','接続数増加に伴う一時的な上昇。30分後に自然回復。','鈴木','山田','closed','memory_high'),
('2026-04-10','07:45:22',(SELECT id FROM hosts WHERE hostname='WEB-PROD-02'),
  'sshd: Failed password for deploy from 10.0.0.30 port 55123 ssh2. Account locked after 5 failures.',
  'セキュリティT','デプロイ用アカウントのパスワード有効期限切れ。パスワード更新とロック解除を実施。','山田','鈴木','responded','auth_fail');

-- AP-PROD-02 (3件)
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-06','13:22:18',(SELECT id FROM hosts WHERE hostname='AP-PROD-02'),
  'WARNING: CPU usage reached 85% for 10 minutes. Top process: java (PID 23456)',
  '運用T','GCログ確認。Full GC多発のためヒープサイズを4G→6Gに変更。','佐藤','山田','closed','cpu_high'),
('2026-04-06','09:30:15',(SELECT id FROM hosts WHERE hostname='AP-PROD-02'),
  'CRITICAL: CPU usage reached 99% for 2 minutes. Top process: java (PID 67890)',
  '運用T',NULL,'山田',NULL,'new','cpu_high'),
('2026-04-09','13:55:30',(SELECT id FROM hosts WHERE hostname='AP-PROD-02'),
  'Service tomcat is not running. systemctl status: failed',
  '運用T',NULL,'佐藤',NULL,'new','service_down');

-- DB-PROD-02 (2件)
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-13','18:20:08',(SELECT id FROM hosts WHERE hostname='DB-PROD-02'),
  'Service postgresql is not running. systemctl status: inactive',
  '運用T','レプリケーション接続断によるPostgreSQL停止。primary側のpg_hba.conf確認後再起動。','佐藤','鈴木','closed','service_down'),
('2026-04-03','10:20:44',(SELECT id FROM hosts WHERE hostname='DB-PROD-02'),
  'PostgreSQL レプリケーション遅延が30秒を超過しました',
  '運用T','ネットワーク輻輳によるWAL転送遅延。輻輳解消後に追いつき確認。','佐藤','山田','closed',NULL);

-- NW-DIST-01 (3件)
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, source_device, interface_no, event_keyword) VALUES
('2026-03-07','22:30:45',(SELECT id FROM hosts WHERE hostname='NW-DIST-01'),
  'SNMP Trap: Interface GigabitEthernet1/0/24 link down (ifIndex: 10124)',
  '運用T','夜間メンテナンス作業によるもの。計画作業のため静観。','田中','鈴木','closed','NW-DIST-01','10124','linkDown'),
('2026-03-07','23:45:12',(SELECT id FROM hosts WHERE hostname='NW-DIST-01'),
  'SNMP Trap: Interface GigabitEthernet1/0/24 link up (ifIndex: 10124)',
  '運用T','メンテナンス完了。linkUp確認。','田中','鈴木','closed','NW-DIST-01','10124','linkUp'),
('2026-04-03','07:05:11',(SELECT id FROM hosts WHERE hostname='NW-DIST-01'),
  'SNMP Trap: Interface GigabitEthernet1/0/12 link down (ifIndex: 10112)',
  '運用T',NULL,'鈴木',NULL,'new','NW-DIST-01','10112','linkDown');

-- LB-01 (2件)
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, source_device, event_keyword) VALUES
('2026-03-21','15:20:19',(SELECT id FROM hosts WHERE hostname='LB-01'),
  'Pool member WEB-PROD-01:443 status changed to DOWN. Health check failed.',
  '運用T','WEB-PROD-01のnginx再起動中に一時的にヘルスチェック失敗。再起動完了後にUP復帰。','鈴木','田中','closed','LB-01','service_down'),
('2026-04-11','10:20:18',(SELECT id FROM hosts WHERE hostname='LB-01'),
  'Pool member AP-PROD-02:8080 status changed to DOWN. Health check failed.',
  '運用T',NULL,NULL,NULL,'new','LB-01','service_down');

-- DNS-01 (3件)
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-04','13:20:22',(SELECT id FROM hosts WHERE hostname='DNS-01'),
  'named: zone example.com/IN: refresh: could not set file modification time: Permission denied',
  '運用T','SELinux設定変更後の権限不整合。restoreconで修正。','田中','鈴木','closed',NULL),
('2026-03-23','09:15:22',(SELECT id FROM hosts WHERE hostname='DNS-01'),
  'Service named is not running. systemctl status: inactive (dead)',
  '運用T','ゾーンファイルのシンタックスエラー。named-checkzoneで修正後に再起動。','田中','鈴木','closed','service_down'),
('2026-04-05','14:30:22',(SELECT id FROM hosts WHERE hostname='DNS-01'),
  'named: zone internal.example.com/IN: serial number unchanged. Zone may fail to transfer.',
  '運用T',NULL,'田中',NULL,'responded',NULL);

-- NTP-01 (2件)
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-09','07:45:33',(SELECT id FROM hosts WHERE hostname='NTP-01'),
  'ntpd: no servers reachable. Clock may drift.',
  '運用T','上位NTPサーバ(ntp.nict.jp)への到達性問題。ファイアウォールルール確認し復旧。','田中','山田','closed','service_down'),
('2026-04-08','19:20:33',(SELECT id FROM hosts WHERE hostname='NTP-01'),
  'ntpd: clock step detected: offset 128.500 seconds.',
  '運用T',NULL,'田中',NULL,'new',NULL);

-- PROXY-01 (2件)
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-27','15:40:18',(SELECT id FROM hosts WHERE hostname='PROXY-01'),
  'Service squid is not running. systemctl status: failed',
  '運用T','キャッシュディレクトリの権限変更が原因。chownで修正後に再起動。','鈴木','佐藤','closed','service_down'),
('2026-04-14','11:10:33',(SELECT id FROM hosts WHERE hostname='PROXY-01'),
  'Service squid is not running. systemctl status: failed. Reason: cache_dir permission denied',
  '運用T',NULL,NULL,NULL,'new','service_down');

-- VM-HOST-02 (2件)
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, source_device, event_keyword) VALUES
('2026-03-10','21:15:18',(SELECT id FROM hosts WHERE hostname='VM-HOST-02'),
  'VMware vCenter: Virtual machine [AP-PROD-02] heartbeat not detected (vmwVmHBLost)',
  '運用T','VMware Toolsの一時的な応答遅延。ゲストOS上では正常動作。VMware Tools再起動で解消。','佐藤','山田','closed','VM-HOST-02','vm_ha'),
('2026-04-13','04:30:22',(SELECT id FROM hosts WHERE hostname='VM-HOST-02'),
  'VMware vCenter: Virtual machine [WEB-PROD-01] heartbeat not detected (vmwVmHBLost)',
  '運用T',NULL,NULL,NULL,'new','VM-HOST-02','vm_ha');

-- FILE-01 (1件)
INSERT INTO logs (event_date, event_time, host_id, message, team, response, assignee, reviewer, status, event_keyword) VALUES
('2026-03-12','11:05:33',(SELECT id FROM hosts WHERE hostname='FILE-01'),
  'CRITICAL: Disk usage on /share reached 97%. Threshold: 90%',
  '運用T','各部門に不要ファイル削除を依頼。一時的に500GB追加割当。','山田','鈴木','closed','disk_usage');
