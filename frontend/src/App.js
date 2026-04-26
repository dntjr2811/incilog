import React, { useState, useEffect, useCallback, useRef, useLayoutEffect } from 'react';
import './App.css';

const API = '/api';
const DEFAULT_CATEGORIES = ['Web','AP','DB','NW','VM','Batch','Backup','Mail','Storage','Infra','監視','other'];
const DEFAULT_TEAMS = ['運用T','開発T','セキュリティT'];
const CAT_KEY = 'incilog_categories';
const TEAM_KEY = 'incilog_teams';
function loadList(key, def) { try { const s = localStorage.getItem(key); return s ? JSON.parse(s) : def; } catch { return def; } }
function saveList(key, val) { localStorage.setItem(key, JSON.stringify(val)); }
async function apiFetch(path, opts = {}) { const r = await fetch(`${API}${path}`, { headers: { 'Content-Type': 'application/json' }, ...opts }); if (!r.ok) throw new Error(r.status); return r.json(); }

function App() {
  const [tab, setTab] = useState('logs');
  const [stats, setStats] = useState(null);
  const [teams, setTeams] = useState(loadList(TEAM_KEY, DEFAULT_TEAMS));
  useEffect(() => { apiFetch('/stats').then(setStats).catch(console.error); }, [tab]);
  const updateTeams = (t) => { setTeams(t); saveList(TEAM_KEY, t); };
  const tabs = [{ id:'logs', label:'アラームログ', icon:'🔔' },{ id:'hosts', label:'ホスト管理', icon:'🖥️' },{ id:'teams', label:'チーム管理', icon:'👥' },{ id:'templates', label:'テンプレート', icon:'📋' },{ id:'stats', label:'統計', icon:'📊' }];
  return (
    <div className="app">
      <header className="app-header"><div className="header-left"><h1 className="app-title">ログ管理</h1><span className="app-subtitle">アラーム対応管理ツール</span></div>
        <div className="header-right">{stats && <div className="header-stats"><span className="stat-badge new">{stats.new} 未対応</span><span className="stat-badge responded">{stats.responded} 対応済</span><span className="stat-badge total">{stats.total} 件</span></div>}</div></header>
      <nav className="tab-nav">{tabs.map(t => <button key={t.id} className={`tab-btn ${tab===t.id?'active':''}`} onClick={()=>setTab(t.id)}><span className="tab-icon">{t.icon}</span>{t.label}</button>)}</nav>
      <main className="main-content">
        {tab==='logs'&&<LogsPage teams={teams}/>}
        {tab==='hosts'&&<HostsPage/>}
        {tab==='teams'&&<TeamsPage teams={teams} onUpdate={updateTeams}/>}
        {tab==='templates'&&<TemplatesPage teams={teams}/>}
        {tab==='stats'&&<StatsPage/>}
      </main>
    </div>
  );
}

// ============================================
// Logs Page
// ============================================
function LogsPage({ teams }) {
  const [logs, setLogs] = useState([]); const [total, setTotal] = useState(0); const [selectedIds, setSelectedIds] = useState([]); const [similarMap, setSimilarMap] = useState({});
  const [filters, setFilters] = useState({ status:'', team:'', host:'', search:'' }); const [hosts, setHosts] = useState([]); const [showAdd, setShowAdd] = useState(false); const [showCsv, setShowCsv] = useState(false); const [loading, setLoading] = useState(false);
  const fetchLogs = useCallback(async () => {
    setLoading(true);
    try { const p = new URLSearchParams(); if(filters.status) p.set('status',filters.status); if(filters.team) p.set('team',filters.team); if(filters.host) p.set('host',filters.host); p.set('limit','300');
      const d = await apiFetch(`/logs?${p}`); let f = d.logs;
      if(filters.search){ const s=filters.search.toLowerCase(); f=f.filter(l=>l.message.toLowerCase().includes(s)||(l.response&&l.response.toLowerCase().includes(s))||(l.hostname&&l.hostname.toLowerCase().includes(s))); }
      setLogs(f); setTotal(f.length);
    } catch(e){ console.error(e); } setLoading(false);
  }, [filters]);
  useEffect(()=>{ fetchLogs(); },[fetchLogs]);
  useEffect(()=>{ apiFetch('/hosts').then(setHosts).catch(console.error); },[]);
  const toggleSelect = async (log) => { const id=log.id; if(selectedIds.includes(id)){ setSelectedIds(p=>p.filter(x=>x!==id)); setSimilarMap(p=>{const n={...p};delete n[id];return n;}); } else { setSelectedIds(p=>[...p,id]); try{const d=await apiFetch(`/logs/${id}/similar`);setSimilarMap(p=>({...p,[id]:d}));}catch(e){setSimilarMap(p=>({...p,[id]:{similar_logs:[],match_criteria:{}}}));} } };
  const updateLog = async (id,u) => { try{await apiFetch(`/logs/${id}`,{method:'PATCH',body:JSON.stringify(u)});fetchLogs();}catch(e){console.error(e);} };
  const selectedLogs = logs.filter(l=>selectedIds.includes(l.id));
  return (
    <div className="logs-page">
      <div className="filters-bar">
        <div className="search-box"><span className="search-icon">🔍</span><input placeholder="メッセージ検索..." value={filters.search} onChange={e=>setFilters(f=>({...f,search:e.target.value}))} /></div>
        <select value={filters.status} onChange={e=>setFilters(f=>({...f,status:e.target.value}))}><option value="">全ステータス</option><option value="new">🔴 未対応</option><option value="responded">🟡 対応済</option><option value="closed">🟢 完了</option></select>
        <select value={filters.team} onChange={e=>setFilters(f=>({...f,team:e.target.value}))}><option value="">全チーム</option>{teams.map(t=><option key={t} value={t}>{t}</option>)}</select>
        <select value={filters.host} onChange={e=>setFilters(f=>({...f,host:e.target.value}))}><option value="">全ホスト</option>{hosts.map(h=><option key={h.id} value={h.hostname}>{h.hostname}</option>)}</select>
        <span className="filter-count">{total}件</span>
        <button className="btn btn-primary" onClick={()=>setShowAdd(true)}>＋ 追加</button>
        <button className="btn btn-secondary" onClick={()=>setShowCsv(true)}>📄 一括取込</button>
      </div>
      {showAdd && <AddLogForm hosts={hosts} teams={teams} onClose={()=>setShowAdd(false)} onSaved={()=>{setShowAdd(false);fetchLogs();}} />}
      {showCsv && <CsvPasteModal onClose={()=>setShowCsv(false)} onDone={()=>{setShowCsv(false);fetchLogs();}} />}
      <div className="split-panel">
        <div className="panel-left">
          <div className="panel-header"><h3>📋 ログ一覧</h3><button className="btn btn-small" onClick={()=>{setSelectedIds(selectedIds.length===logs.length?[]:logs.map(l=>l.id));setSimilarMap({});}}>{selectedIds.length===logs.length?'全解除':'全選択'}</button></div>
          <div className="log-list">{loading&&<div className="loading">読み込み中...</div>}{logs.map(log=><LogCard key={log.id} log={log} selected={selectedIds.includes(log.id)} onClick={()=>toggleSelect(log)} />)}{!loading&&logs.length===0&&<div className="empty">ログがありません</div>}</div>
        </div>
        <div className="panel-right">
          {selectedLogs.length > 0
            ? <ConnectedView logs={selectedLogs} similarMap={similarMap} onUpdate={updateLog} />
            : <div className="no-selection"><div className="no-selection-icon">👈</div><p>左のログを選択すると詳細と類似過去アラームが表示されます</p><p className="no-selection-hint">複数選択可能です</p></div>}
        </div>
      </div>
    </div>
  );
}

// ============================================
// Connected View — fixed: no MutationObserver
// ============================================
function ConnectedView({ logs, similarMap, onUpdate }) {
  const containerRef = useRef(null);
  const detailRefs = useRef({});
  const similarRefs = useRef({});
  const [curves, setCurves] = useState([]);
  const [svgSize, setSvgSize] = useState({ w: 0, h: 0 });
  const rafRef = useRef(null);

  const calcCurves = useCallback(() => {
    if (rafRef.current) cancelAnimationFrame(rafRef.current);
    rafRef.current = requestAnimationFrame(() => {
      const ct = containerRef.current;
      if (!ct) return;
      setSvgSize({ w: ct.scrollWidth, h: ct.scrollHeight });
      const newCurves = [];
      const ctRect = ct.getBoundingClientRect();
      const scrollY = ct.scrollTop;
      logs.forEach(log => {
        const sd = similarMap[log.id];
        if (!sd || sd.similar_logs.length === 0) return;
        const dEl = detailRefs.current[log.id];
        const sEl = similarRefs.current[log.id];
        if (!dEl || !sEl) return;
        const dr = dEl.getBoundingClientRect();
        const sr = sEl.getBoundingClientRect();
        newCurves.push({
          x1: dr.right - ctRect.left,
          y1: dr.top - ctRect.top + scrollY + dr.height / 2,
          x2: sr.left - ctRect.left,
          y2: sr.top - ctRect.top + scrollY + 20,
        });
      });
      setCurves(newCurves);
    });
  }, [logs, similarMap]);

  useLayoutEffect(() => {
    const t1 = setTimeout(calcCurves, 100);
    const t2 = setTimeout(calcCurves, 500);
    return () => { clearTimeout(t1); clearTimeout(t2); };
  }, [calcCurves]);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    el.addEventListener('scroll', calcCurves);
    window.addEventListener('resize', calcCurves);
    return () => { el.removeEventListener('scroll', calcCurves); window.removeEventListener('resize', calcCurves); };
  }, [calcCurves]);

  const hasSimilarLogs = logs.filter(l => similarMap[l.id]?.similar_logs?.length > 0);

  return (
    <div className="connected-container" ref={containerRef}>
      <svg className="connector-overlay" width={svgSize.w||'100%'} height={svgSize.h||'100%'}
        viewBox={`0 0 ${svgSize.w||100} ${svgSize.h||100}`}>
        {curves.map((c, i) => {
          const cpx1 = c.x1 + (c.x2 - c.x1) * 0.4;
          const cpx2 = c.x1 + (c.x2 - c.x1) * 0.6;
          return <g key={i}>
            <path d={`M ${c.x1} ${c.y1} C ${cpx1} ${c.y1}, ${cpx2} ${c.y2}, ${c.x2} ${c.y2}`}
              fill="none" stroke="var(--accent)" strokeWidth="1.5" strokeDasharray="5 3" opacity="0.45" />
            <circle cx={c.x1} cy={c.y1} r="3.5" fill="var(--accent)" opacity="0.7" />
            <circle cx={c.x2} cy={c.y2} r="3.5" fill="var(--accent)" opacity="0.5" />
          </g>;
        })}
      </svg>
      <div className="detail-column">
        {logs.map(log => (
          <div key={log.id} ref={el => { detailRefs.current[log.id] = el; }}>
            <LogDetail log={log} onUpdate={u => onUpdate(log.id, u)} onLayoutChange={calcCurves} />
          </div>
        ))}
      </div>
      <div className="similar-column">
        {hasSimilarLogs.map(log => {
          const sd = similarMap[log.id];
          return (
            <div key={log.id} ref={el => { similarRefs.current[log.id] = el; }}>
              <SimilarGroup similar={sd.similar_logs} criteria={sd.match_criteria||{}} sourceLog={log} onLayoutChange={calcCurves} />
            </div>
          );
        })}
        {hasSimilarLogs.length === 0 && <div className="empty">類似アラームなし</div>}
      </div>
    </div>
  );
}

function SimilarGroup({ similar, criteria, sourceLog, onLayoutChange }) {
  const [expanded, setExpanded] = useState(false);
  // 類似度降順で表示（バックエンド側でソート済みだが念のためフロントでも保証）
  const sorted = [...similar].sort((a, b) => (b.similarity ?? 0) - (a.similarity ?? 0));
  const display = expanded ? sorted : sorted.slice(0, 1);
  const toggle = () => { setExpanded(!expanded); setTimeout(onLayoutChange, 50); };
  return (
    <div className="similar-group">
      <div className="similar-group-header">
        <span className="similar-label">類似 ({similar.length})</span>
        <span className="similar-source">{sourceLog.event_date} {sourceLog.hostname}</span>
        {similar.length > 1 && <button className="btn btn-small btn-toggle" onClick={toggle}>{expanded ? '▲ 折りたたむ' : `▼ 全${similar.length}件`}</button>}
      </div>
      {display.map(sl => <SimilarCard key={sl.id} log={sl} />)}
    </div>
  );
}

function LogCard({ log, selected, onClick }) {
  const si={new:'🔴',responded:'🟡',closed:'🟢'};
  return (<div className={`log-card ${selected?'selected':''} ${log.status}`} onClick={onClick}><div className="log-card-top"><span className="log-check">{selected?'☑':'☐'}</span><span className="log-status">{si[log.status]||'⚪'}</span><span className="log-date">{log.event_date} {log.event_time}</span><span className="log-host">{log.hostname}</span></div><div className="log-card-message">{log.message&&log.message.substring(0,120)}</div><div className="log-card-footer">{log.team&&<span className="tag team-tag">{log.team}</span>}{log.message_code&&<span className="tag code-tag">{log.message_code}</span>}{log.event_keyword&&<span className="tag keyword-tag">{log.event_keyword}</span>}{log.org_name&&<span className="tag org-tag">{log.org_name}</span>}</div></div>);
}

// ============================================
// Log Detail — fixed: no freeze on edit
// ============================================
function LogDetail({ log, onUpdate, onLayoutChange }) {
  const [editing, setEditing] = useState(false);
  const [response, setResponse] = useState(log.response || '');
  const [assignee, setAssignee] = useState(log.assignee || '');
  const [reviewer, setReviewer] = useState(log.reviewer || '');
  const [status, setStatus] = useState(log.status);
  const [tpls, setTpls] = useState([]);

  // Only reset when log ID changes, NOT on every field change
  useEffect(() => {
    setResponse(log.response || '');
    setAssignee(log.assignee || '');
    setReviewer(log.reviewer || '');
    setStatus(log.status);
    setEditing(false);
    apiFetch(`/logs/${log.id}/suggest-templates`).then(setTpls).catch(() => setTpls([]));
  }, [log.id]); // ← dependency only on log.id

  const save = () => {
    onUpdate({ response, assignee, reviewer, status });
    setEditing(false);
  };

  const startEdit = () => {
    setEditing(true);
    if (onLayoutChange) setTimeout(onLayoutChange, 50);
  };

  const cancelEdit = () => {
    setResponse(log.response || '');
    setAssignee(log.assignee || '');
    setReviewer(log.reviewer || '');
    setStatus(log.status);
    setEditing(false);
    if (onLayoutChange) setTimeout(onLayoutChange, 50);
  };

  return (
    <div className="log-detail-card">
      <div className="detail-top">
        <div className="detail-meta">
          <span className={`status-dot ${log.status}`} />
          <span className="detail-date">{log.event_date} {log.event_time}</span>
          <span className="detail-host">{log.hostname}</span>
          {!editing
            ? <button className="btn btn-small" onClick={startEdit}>✏️</button>
            : <div className="edit-buttons"><button className="btn btn-primary btn-small" onClick={save}>💾</button><button className="btn btn-small" onClick={cancelEdit}>✕</button></div>}
        </div>
        <div className="detail-message">{log.message}</div>
        <div className="parsed-fields">
          {log.message_code&&<span className="tag code-tag">{log.message_code}</span>}
          {log.jobnet_path&&<span className="tag">ジョブ:{log.jobnet_path}</span>}
          {log.org_name&&<span className="tag org-tag">{log.org_name}</span>}
          {log.source_device&&<span className="tag keyword-tag">{log.source_device}</span>}
          {log.interface_no&&<span className="tag">IF:{log.interface_no}</span>}
          {log.event_keyword&&<span className="tag keyword-tag">{log.event_keyword}</span>}
        </div>
      </div>
      <div className="detail-fields">
        <div className="field-row"><label>担当者</label>{editing?<input value={assignee} onChange={e=>setAssignee(e.target.value)} placeholder="担当者名"/>:<span>{log.assignee||'-'}</span>}</div>
        <div className="field-row"><label>確認者</label>{editing?<input value={reviewer} onChange={e=>setReviewer(e.target.value)} placeholder="確認者名"/>:<span>{log.reviewer||'-'}</span>}</div>
        <div className="field-row"><label>ステータス</label>{editing?<select value={status} onChange={e=>setStatus(e.target.value)}><option value="new">未対応</option><option value="responded">対応済</option><option value="closed">完了</option></select>:<span className={`status-label ${log.status}`}>{log.status}</span>}</div>
        <div className="field-row full"><label>対応内容</label>{editing?(<><textarea value={response} onChange={e=>setResponse(e.target.value)} rows={3} placeholder="対応内容"/>{tpls.length>0&&<div className="tpl-suggest">{tpls.map(t=><button key={t.id} className="btn btn-template" onClick={()=>setResponse(t.content)}>📋 {t.title}</button>)}</div>}</>):<div className="response-text">{log.response||'未入力'}</div>}</div>
      </div>
    </div>
  );
}

function SimilarCard({ log }) {
  const [open,setOpen]=useState(false);
  // 類似度をパーセント表示（vector検索結果は0〜1の値、exactなど無い場合はnull）
  const simPct = (log.similarity != null) ? Math.round(log.similarity * 100) : null;
  return (<div className={`similar-card ${open?'open':''}`} onClick={()=>setOpen(!open)}><div className="similar-top">{simPct!=null&&<span className="similar-score" title={`類似度 ${log.similarity}`}>{simPct}%</span>}<span className="similar-date">{log.event_date}</span><span className="similar-host">{log.hostname}</span>{log.org_name&&<span className="tag org-tag">{log.org_name}</span>}</div>{!open&&log.response&&<div className="similar-preview">💡 {log.response.substring(0,80)}</div>}{open&&<div className="similar-expanded"><div className="similar-msg">{log.message&&log.message.substring(0,200)}</div><div className="similar-resp"><strong>対応:</strong><pre>{log.response}</pre></div><div className="similar-who">担当:{log.assignee||'-'} / 確認:{log.reviewer||'-'}</div></div>}</div>);
}

function AddLogForm({ hosts, teams, onClose, onSaved }) {
  const [f,setF]=useState({event_date:new Date().toISOString().split('T')[0],event_time:new Date().toTimeString().substring(0,8),hostname:'',message:'',team:''});
  const submit=async()=>{if(!f.hostname||!f.message)return alert('ホスト名とメッセージは必須');try{await apiFetch('/logs',{method:'POST',body:JSON.stringify(f)});onSaved();}catch(e){alert('追加失敗');}};
  return (<div className="modal-overlay" onClick={onClose}><div className="modal" onClick={e=>e.stopPropagation()}><div className="modal-header"><h3>＋ ログ追加</h3><button className="btn btn-small" onClick={onClose}>✕</button></div><div className="modal-body"><div className="form-row"><label>日付</label><input type="date" value={f.event_date} onChange={e=>setF(x=>({...x,event_date:e.target.value}))}/></div><div className="form-row"><label>時刻</label><input type="time" step="1" value={f.event_time} onChange={e=>setF(x=>({...x,event_time:e.target.value}))}/></div><div className="form-row"><label>ホスト名</label><select value={f.hostname} onChange={e=>setF(x=>({...x,hostname:e.target.value}))}><option value="">選択</option>{hosts.map(h=><option key={h.id} value={h.hostname}>{h.hostname}</option>)}</select></div><div className="form-row"><label>担当T</label><select value={f.team} onChange={e=>setF(x=>({...x,team:e.target.value}))}><option value="">選択</option>{teams.map(t=><option key={t} value={t}>{t}</option>)}</select></div><div className="form-row"><label>メッセージ</label><textarea value={f.message} rows={4} onChange={e=>setF(x=>({...x,message:e.target.value}))} placeholder="アラームメッセージ"/></div></div><div className="modal-footer"><button className="btn btn-secondary" onClick={onClose}>キャンセル</button><button className="btn btn-primary" onClick={submit}>追加</button></div></div></div>);
}

function CsvPasteModal({ onClose, onDone }) {
  const [text,setText]=useState(''); const [importing,setImporting]=useState(false); const [result,setResult]=useState(null);
  const parseRows=(raw)=>{const ls=raw.split('\n').filter(l=>l.trim());if(ls.length<2)return[];const sep=ls[0].includes('\t')?'\t':',';const hs=ls[0].split(sep).map(h=>h.trim());return ls.slice(1).map(l=>{const cs=l.split(sep);const r={};hs.forEach((h,i)=>{r[h]=(cs[i]||'').trim();});return r;});};
  const doImport=async()=>{const rows=parseRows(text);if(!rows.length)return alert('データ認識不可');setImporting(true);let s=0,f=0;
    for(const row of rows){try{const dF=row['イベント登録日']||row['event_date']||'';const tF=row['イベント登録時刻']||row['event_time']||'';const hF=row['イベント発行元ホスト名']||row['hostname']||'';const mF=row['メッセージ']||row['message']||'';const tmF=row['担当T']||row['team']||'';const rF=row['対応内容']||row['response']||'';const aF=row['担当者']||row['assignee']||'';const rvF=row['確認者']||row['reviewer']||'';if(!hF||!mF){f++;continue;}const body={event_date:dF.replace(/\//g,'-'),event_time:tF||'00:00:00',hostname:hF,message:mF,team:tmF||null};const c=await apiFetch('/logs',{method:'POST',body:JSON.stringify(body)});if(rF||aF||rvF){const u={};if(rF){u.response=rF;u.status='responded';}if(aF)u.assignee=aF;if(rvF)u.reviewer=rvF;await apiFetch(`/logs/${c.id}`,{method:'PATCH',body:JSON.stringify(u)});}s++;}catch(e){f++;}}
    setResult({success:s,fail:f,total:rows.length});setImporting(false);};
  const pv=text?parseRows(text).slice(0,3):[];
  return (<div className="modal-overlay" onClick={onClose}><div className="modal modal-wide" onClick={e=>e.stopPropagation()}><div className="modal-header"><h3>📄 一括取込</h3><button className="btn btn-small" onClick={onClose}>✕</button></div><div className="modal-body"><div className="csv-info"><p>Excelからヘッダ行ごとコピーして貼り付け（タブ区切り）</p><p>カラム: <code>イベント登録日</code> <code>イベント登録時刻</code> <code>イベント発行元ホスト名</code> <code>メッセージ</code> <code>担当T</code> <code>対応内容</code> <code>確認者</code></p></div><textarea className="csv-textarea" value={text} onChange={e=>setText(e.target.value)} rows={10} placeholder="ここに貼り付け..."/>{pv.length>0&&!result&&<div className="csv-preview"><h4>プレビュー ({parseRows(text).length}件中 先頭3件)</h4><div className="csv-table-wrap"><table className="csv-table"><thead><tr>{Object.keys(pv[0]).map(k=><th key={k}>{k}</th>)}</tr></thead><tbody>{pv.map((row,i)=><tr key={i}>{Object.values(row).map((v,j)=><td key={j}>{v.substring(0,50)}</td>)}</tr>)}</tbody></table></div></div>}{result&&<div className="csv-result">✅ {result.success}件成功 / ❌ {result.fail}件失敗 / 全{result.total}件</div>}</div><div className="modal-footer"><button className="btn btn-secondary" onClick={onClose}>{result?'閉じる':'キャンセル'}</button>{!result&&<button className="btn btn-primary" onClick={doImport} disabled={!text.trim()||importing}>{importing?'取込中...':'取込実行'}</button>}{result&&<button className="btn btn-primary" onClick={onDone}>完了</button>}</div></div></div>);
}

// ============================================
// Teams Page
// ============================================
function TeamsPage({ teams, onUpdate }) {
  const [newTeam, setNewTeam] = useState('');
  const [editIdx, setEditIdx] = useState(null);
  const [editName, setEditName] = useState('');

  const addTeam = () => {
    if (!newTeam.trim() || teams.includes(newTeam.trim())) return;
    onUpdate([...teams, newTeam.trim()]); setNewTeam('');
  };
  const removeTeam = (t) => { onUpdate(teams.filter(x => x !== t)); };
  const startEdit = (i) => { setEditIdx(i); setEditName(teams[i]); };
  const saveEdit = () => {
    if (!editName.trim() || (editName.trim() !== teams[editIdx] && teams.includes(editName.trim()))) { alert('無効または重複'); return; }
    const u = [...teams]; u[editIdx] = editName.trim(); onUpdate(u); setEditIdx(null);
  };

  return (
    <div className="table-page">
      <div className="page-header"><h2>👥 チーム管理</h2></div>
      <div className="team-info">チーム名はログのフィルタ、ログ追加、テンプレートで使用されます。ブラウザに保存されます。</div>
      <div className="team-list">
        {teams.map((t, i) => (
          <div key={i} className="team-item">
            {editIdx === i ? (
              <>
                <input className="team-edit-input" value={editName} onChange={e => setEditName(e.target.value)}
                  onKeyDown={e => { if (e.key === 'Enter') saveEdit(); if (e.key === 'Escape') setEditIdx(null); }} autoFocus />
                <button className="btn-cat-action save" onClick={saveEdit}>✓</button>
                <button className="btn-cat-action cancel" onClick={() => setEditIdx(null)}>✕</button>
              </>
            ) : (
              <>
                <span className="team-name">{t}</span>
                <button className="btn-cat-action edit" onClick={() => startEdit(i)}>✏️</button>
                <button className="btn-cat-action del" onClick={() => removeTeam(t)}>✕</button>
              </>
            )}
          </div>
        ))}
      </div>
      <div className="team-add-row">
        <input placeholder="新しいチーム名" value={newTeam} onChange={e => setNewTeam(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && addTeam()} />
        <button className="btn btn-primary" onClick={addTeam}>追加</button>
      </div>
    </div>
  );
}

// ============================================
// Hosts Page
// ============================================
function HostsPage() {
  const [hosts,setHosts]=useState([]); const [editId,setEditId]=useState(null); const [editData,setEditData]=useState({}); const [showAdd,setShowAdd]=useState(false);
  const [newHost,setNewHost]=useState({hostname:'',description:'',category:'',notes:''});
  const [categories,setCategories]=useState(loadList(CAT_KEY, DEFAULT_CATEGORIES)); const [showCat,setShowCat]=useState(false); const [newCat,setNewCat]=useState('');
  const [editingCat,setEditingCat]=useState(null); const [editCatName,setEditCatName]=useState('');
  const fetchH=()=>apiFetch('/hosts').then(setHosts).catch(console.error); useEffect(()=>{fetchH();},[]);
  const updateCats=(u)=>{setCategories(u);saveList(CAT_KEY,u);};
  const addCat=()=>{if(!newCat.trim()||categories.includes(newCat.trim()))return;updateCats([...categories,newCat.trim()]);setNewCat('');};
  const rmCat=(c)=>{if(hosts.some(h=>h.category===c))return alert(`「${c}」は使用中`);updateCats(categories.filter(x=>x!==c));};
  const startEditCat=(c)=>{setEditingCat(c);setEditCatName(c);};
  const saveEditCat=()=>{if(!editCatName.trim()||(editCatName.trim()!==editingCat&&categories.includes(editCatName.trim()))){alert('無効または重複');return;}updateCats(categories.map(c=>c===editingCat?editCatName.trim():c));setEditingCat(null);};
  const startEdit=(h)=>{setEditId(h.id);setEditData({hostname:h.hostname,description:h.description||'',category:h.category||'',notes:h.notes||''});};
  const saveEdit=async()=>{try{await apiFetch(`/hosts/${editId}`,{method:'PATCH',body:JSON.stringify(editData)});setEditId(null);fetchH();}catch(e){alert('失敗');}};
  const addHost=async()=>{if(!newHost.hostname)return alert('ホスト名必須');try{await apiFetch('/hosts',{method:'POST',body:JSON.stringify(newHost)});setShowAdd(false);setNewHost({hostname:'',description:'',category:'',notes:''});fetchH();}catch(e){alert('失敗');}};
  return (
    <div className="table-page"><div className="page-header"><h2>🖥️ ホスト管理</h2><div style={{display:'flex',gap:6}}><button className="btn btn-secondary" onClick={()=>setShowCat(!showCat)}>🏷️ カテゴリ管理</button><button className="btn btn-primary" onClick={()=>setShowAdd(!showAdd)}>＋ 追加</button></div></div>
      {showCat&&<div className="cat-manager"><div className="cat-manager-header"><h4>カテゴリ管理</h4></div><div className="cat-list">{categories.map(c=><div key={c} className="cat-item">{editingCat===c?(<><input className="cat-edit-input" value={editCatName} onChange={e=>setEditCatName(e.target.value)} onKeyDown={e=>{if(e.key==='Enter')saveEditCat();if(e.key==='Escape')setEditingCat(null);}} autoFocus/><button className="btn-cat-action save" onClick={saveEditCat}>✓</button><button className="btn-cat-action cancel" onClick={()=>setEditingCat(null)}>✕</button></>):(<><span className={`tag cat-${c}`}>{c}</span><button className="btn-cat-action edit" onClick={()=>startEditCat(c)}>✏️</button><button className="btn-cat-action del" onClick={()=>rmCat(c)}>✕</button></>)}</div>)}</div><div className="cat-add-row"><input placeholder="新カテゴリ名" value={newCat} onChange={e=>setNewCat(e.target.value)} onKeyDown={e=>e.key==='Enter'&&addCat()}/><button className="btn btn-primary btn-small" onClick={addCat}>追加</button></div></div>}
      {showAdd&&<div className="inline-form"><input placeholder="ホスト名" value={newHost.hostname} onChange={e=>setNewHost(n=>({...n,hostname:e.target.value}))}/><input placeholder="説明" value={newHost.description} onChange={e=>setNewHost(n=>({...n,description:e.target.value}))}/><select value={newHost.category} onChange={e=>setNewHost(n=>({...n,category:e.target.value}))}><option value="">カテゴリ選択</option>{categories.map(c=><option key={c} value={c}>{c}</option>)}</select><input placeholder="メモ" value={newHost.notes} onChange={e=>setNewHost(n=>({...n,notes:e.target.value}))}/><button className="btn btn-primary" onClick={addHost}>追加</button><button className="btn btn-secondary" onClick={()=>setShowAdd(false)}>取消</button></div>}
      <table className="data-table"><thead><tr><th>ホスト名</th><th>説明</th><th>カテゴリ</th><th>ログ数</th><th>メモ</th><th>操作</th></tr></thead><tbody>{hosts.map(h=><tr key={h.id}>{editId===h.id?(<><td><input value={editData.hostname} onChange={e=>setEditData(d=>({...d,hostname:e.target.value}))}/></td><td><input value={editData.description} onChange={e=>setEditData(d=>({...d,description:e.target.value}))}/></td><td><select value={editData.category} onChange={e=>setEditData(d=>({...d,category:e.target.value}))}><option value="">選択</option>{categories.map(c=><option key={c} value={c}>{c}</option>)}</select></td><td className="num">{h.log_count}</td><td><input value={editData.notes} onChange={e=>setEditData(d=>({...d,notes:e.target.value}))}/></td><td><button className="btn btn-primary btn-small" onClick={saveEdit}>💾</button><button className="btn btn-small" onClick={()=>setEditId(null)}>✕</button></td></>):(<><td className="mono">{h.hostname}</td><td>{h.description}</td><td><span className="tag">{h.category||'-'}</span></td><td className="num">{h.log_count}</td><td className="notes">{h.notes||'-'}</td><td><button className="btn btn-small" onClick={()=>startEdit(h)}>✏️</button></td></>)}</tr>)}</tbody></table>
    </div>
  );
}

function TemplatesPage({ teams }) {
  const [tpls,setTpls]=useState([]); const [showAdd,setShowAdd]=useState(false); const [f,setF]=useState({title:'',content:'',team:'',match_code:'',match_device:'',match_keyword:''});
  const fetch_=()=>apiFetch('/templates').then(setTpls).catch(console.error); useEffect(()=>{fetch_();},[]);
  const add=async()=>{if(!f.title||!f.content)return alert('タイトルと内容必須');const d={...f};Object.keys(d).forEach(k=>{if(d[k]==='')d[k]=null;});try{await apiFetch('/templates',{method:'POST',body:JSON.stringify(d)});setShowAdd(false);setF({title:'',content:'',team:'',match_code:'',match_device:'',match_keyword:''});fetch_();}catch(e){alert('失敗');}};
  return (
    <div className="table-page"><div className="page-header"><h2>📋 テンプレート</h2><button className="btn btn-primary" onClick={()=>setShowAdd(!showAdd)}>＋ 追加</button></div>
      {showAdd&&<div className="inline-form template-form"><input placeholder="タイトル" value={f.title} onChange={e=>setF(x=>({...x,title:e.target.value}))}/><div style={{display:'flex',gap:8}}><select value={f.team} onChange={e=>setF(x=>({...x,team:e.target.value}))}><option value="">チーム</option>{teams.map(t=><option key={t} value={t}>{t}</option>)}</select><input placeholder="コード" value={f.match_code} onChange={e=>setF(x=>({...x,match_code:e.target.value}))}/><input placeholder="機器" value={f.match_device} onChange={e=>setF(x=>({...x,match_device:e.target.value}))}/><input placeholder="キーワード" value={f.match_keyword} onChange={e=>setF(x=>({...x,match_keyword:e.target.value}))}/></div><textarea placeholder="対応内容" value={f.content} rows={3} onChange={e=>setF(x=>({...x,content:e.target.value}))}/><div className="form-actions"><button className="btn btn-primary" onClick={add}>追加</button><button className="btn btn-secondary" onClick={()=>setShowAdd(false)}>取消</button></div></div>}
      <div className="template-grid">{tpls.map(t=><div key={t.id} className="template-card"><div className="template-card-header"><h4>{t.title}</h4>{t.team&&<span className="tag team-tag">{t.team}</span>}</div><pre className="template-content">{t.content}</pre><div className="template-match">{t.match_code&&<span className="tag code-tag">コード:{t.match_code}</span>}{t.match_device&&<span className="tag keyword-tag">機器:{t.match_device}</span>}{t.match_keyword&&<span className="tag keyword-tag">種別:{t.match_keyword}</span>}</div></div>)}</div>
    </div>
  );
}

function StatsPage() {
  const [stats,setStats]=useState(null); useEffect(()=>{apiFetch('/stats').then(setStats).catch(console.error);},[]);if(!stats)return<div className="loading">読み込み中...</div>;const mx=Math.max(...Object.values(stats.top_hosts||{}),1);
  return (<div className="stats-page"><h2>📊 統計</h2><div className="stats-cards"><div className="stats-card total"><div className="stats-number">{stats.total}</div><div className="stats-label">総件数</div></div><div className="stats-card new"><div className="stats-number">{stats.new}</div><div className="stats-label">未対応</div></div><div className="stats-card responded"><div className="stats-number">{stats.responded}</div><div className="stats-label">対応済</div></div><div className="stats-card closed"><div className="stats-number">{stats.closed}</div><div className="stats-label">完了</div></div></div><div className="stats-sections"><div className="stats-section"><h3>チーム別</h3>{Object.entries(stats.by_team||{}).map(([t,c])=><div key={t} className="stat-bar-row"><span className="stat-bar-label">{t}</span><div className="stat-bar"><div className="stat-bar-fill" style={{width:`${(c/stats.total)*100}%`}}>{c}</div></div></div>)}</div><div className="stats-section"><h3>ホスト別</h3>{Object.entries(stats.top_hosts||{}).map(([h,c])=><div key={h} className="stat-bar-row"><span className="stat-bar-label mono">{h}</span><div className="stat-bar"><div className="stat-bar-fill" style={{width:`${(c/mx)*100}%`}}>{c}</div></div></div>)}</div></div></div>);
}

export default App;
