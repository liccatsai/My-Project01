import { useState, useEffect, useMemo } from "react";

const CATEGORY_CONFIG = {
  "美術": { color: "#FF6B6B", bg: "rgba(255,107,107,0.12)", icon: "🎨" },
  "排程": { color: "#4ECDC4", bg: "rgba(78,205,196,0.12)", icon: "📅" },
  "會議紀錄": { color: "#FFE66D", bg: "rgba(255,230,109,0.12)", icon: "📝" },
  "文件": { color: "#A78BFA", bg: "rgba(167,139,250,0.12)", icon: "📋" },
  "試算表": { color: "#6BCB77", bg: "rgba(107,203,119,0.12)", icon: "📊" },
  "簡報": { color: "#FF9F43", bg: "rgba(255,159,67,0.12)", icon: "📌" },
  "資料夾": { color: "#C8A96E", bg: "rgba(200,169,110,0.12)", icon: "📁" },
  "其他": { color: "#94A3B8", bg: "rgba(148,163,184,0.12)", icon: "🔗" },
};

function formatDate(ts) {
  const d = new Date(ts);
  return `${d.getFullYear()}/${String(d.getMonth() + 1).padStart(2, "0")}/${String(d.getDate()).padStart(2, "0")}`;
}

const STORAGE_KEY = "linkmanager-v2-data";

export default function LinkManager() {
  const [records, setRecords] = useState([]);
  const [loading, setLoading] = useState(true);
  const [inputRaw, setInputRaw] = useState("");
  const [inputUrl, setInputUrl] = useState("");
  const [inputTitle, setInputTitle] = useState("");
  const [inputCategory, setInputCategory] = useState("其他");
  const [inputDesc, setInputDesc] = useState("");
  const [inputTags, setInputTags] = useState("");
  const [suggestedTags, setSuggestedTags] = useState([]);
  const [inputSource, setInputSource] = useState("");
  const [inputRemarks, setInputRemarks] = useState("");
  const [aiLoading, setAiLoading] = useState(false);
  const [aiDone, setAiDone] = useState(false);
  const [panel, setPanel] = useState(false);
  const [search, setSearch] = useState("");
  const [filterCat, setFilterCat] = useState("all");
  const [filterTag, setFilterTag] = useState("");
  const [sortBy, setSortBy] = useState("newest");
  const [editId, setEditId] = useState(null);
  const [copied, setCopied] = useState(null);
  const [toast, setToast] = useState(null);
  const [deleteConfirm, setDeleteConfirm] = useState(null);
  const [duplicateInfo, setDuplicateInfo] = useState(null); // 重複時的資訊

  useEffect(() => {
    (async () => {
      try {
        const r = await window.localStorage?.getItem(STORAGE_KEY);
        if (r) setRecords(JSON.parse(r));
      } catch {}
      setLoading(false);
    })();
  }, []);

  async function saveLocal(data) {
    setRecords(data);
    try {
      localStorage?.setItem(STORAGE_KEY, JSON.stringify(data));
    } catch {}
  }

  function showToast(msg, type = "success") {
    setToast({ msg, type });
    setTimeout(() => setToast(null), 2500);
  }

  async function analyzeInput() {
    if (!inputRaw.trim()) return;
    setAiLoading(true);
    setAiDone(false);
    try {
      const existingTags = [...new Map(
        records.flatMap((r) => r.tags).map((t) => [t.toLowerCase().trim(), t.trim()])
      ).values()];

      // 提取 URL
      const urlMatch = inputRaw.match(/https?:\/\/[^\s]+/);
      const detectedUrl = urlMatch ? urlMatch[0] : "";

      // 调用服务器端分析
      const response = await fetch("/api/analyze", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          inputRaw: inputRaw,
          existingTags: existingTags,
        }),
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.message || "分析失败");
      }

      const parsed = await response.json();

      if (parsed.url) setInputUrl(parsed.url);
      if (parsed.title) setInputTitle(parsed.title);
      if (parsed.desc) setInputDesc(parsed.desc);
      if (parsed.category) setInputCategory(parsed.category);
      if (parsed.tags?.length) {
        setSuggestedTags(parsed.tags);
        setInputTags(parsed.tags.join(", "));
      }
      setInputSource(parsed.source || "");
      setAiDone(true);
    } catch (error) {
      showToast(`AI 分析失敗：${error.message}`, "error");
    }
    setAiLoading(false);
  }

  async function regenDesc() {
    if (!inputUrl) return;
    setAiLoading(true);
    try {
      const response = await fetch("/api/regenerate-desc", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          url: inputUrl,
          title: inputTitle,
          category: inputCategory,
          inputRaw: inputRaw,
        }),
      });

      if (!response.ok) throw new Error("重新生成失敗");

      const data = await response.json();
      if (data.desc) setInputDesc(data.desc);
    } catch (error) {
      showToast(error.message, "error");
    }
    setAiLoading(false);
  }

  function openAdd() {
    setEditId(null);
    setInputRaw("");
    setInputUrl("");
    setInputTitle("");
    setInputCategory("其他");
    setInputDesc("");
    setInputTags("");
    setInputSource("");
    setInputRemarks("");
    setSuggestedTags([]);
    setAiDone(false);
    setDuplicateInfo(null);
    setPanel(true);
  }

  function openEdit(rec) {
    setEditId(rec.id);
    setInputRaw("");
    setInputUrl(rec.url);
    setInputTitle(rec.title);
    setInputCategory(rec.category);
    setInputDesc(rec.desc);
    setInputTags(rec.tags.join(", "));
    setInputSource(rec.source || "");
    setInputRemarks(rec.remarks || "");
    setAiDone(true);
    setPanel(true);
  }

  async function handleSubmit() {
    if (!inputUrl.trim()) return;
    setAiLoading(true);

    try {
      const tags = inputTags
        .split(/[,，\s]+/)
        .map((t) => t.trim())
        .filter(Boolean);
      const newData = {
        url: inputUrl.trim(),
        title: inputTitle.trim() || inputUrl,
        category: inputCategory,
        desc: inputDesc.trim(),
        source: inputSource.trim(),
        remarks: inputRemarks.trim(),
        tags,
      };

      if (editId) {
        // 編輯模式（本地）
        const updated = records.map((r) =>
          r.id === editId ? { ...r, ...newData, updatedAt: Date.now() } : r
        );
        await saveLocal(updated);
        showToast("已更新資料");
        setPanel(false);
      } else {
        // 新增模式 - 存到 Notion
        const response = await fetch("/api/save-link", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(newData),
        });

        if (!response.ok) {
          const error = await response.json();
          throw new Error(error.message || "保存失敗");
        }

        const result = await response.json();

        if (result.isUpdate) {
          // 重複 - 已更新現有記錄
          setDuplicateInfo({
            type: "updated",
            pageUrl: result.pageUrl,
            oldTitle: result.oldTitle,
          });
          showToast(`✅ 已更新現有記錄：${result.oldTitle}`, "success");
        } else {
          // 新記錄已建立
          showToast(`✅ 已存到 Notion：${inputTitle}`, "success");
        }

        // 本地也存一份（離線備份）
        const rec = {
          id: Date.now(),
          ...newData,
          notionUrl: result.pageUrl,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        };
        await saveLocal([rec, ...records]);
        setPanel(false);
      }
    } catch (error) {
      showToast(`錯誤：${error.message}`, "error");
    }
    setAiLoading(false);
  }

  async function handleDelete(id) {
    await saveLocal(records.filter((r) => r.id !== id));
    setDeleteConfirm(null);
    showToast("已刪除", "error");
  }

  function copyCard(rec) {
    const text = `嗨，這邊是連結分享，若有問題再跟我說\n【${rec.title}】\n🔗 連結：${rec.url}${
      rec.desc ? `\n📄 簡述：${rec.desc}` : ""
    }`;
    try {
      navigator.clipboard.writeText(text).then(() => {
        setCopied(rec.id);
        setTimeout(() => setCopied(null), 1800);
      });
    } catch {
      showToast("複製失敗", "error");
    }
  }

  const allTags = useMemo(() => {
    const seen = new Map();
    records.forEach((r) =>
      r.tags.forEach((t) => {
        const key = t.toLowerCase().trim();
        if (key && !seen.has(key)) seen.set(key, t.trim());
      })
    );
    return [...seen.values()];
  }, [records]);

  const filtered = useMemo(() => {
    let res = [...records];
    if (filterCat !== "all") res = res.filter((r) => r.category === filterCat);
    if (filterTag) res = res.filter((r) => r.tags.includes(filterTag));
    if (search.trim()) {
      const q = search.toLowerCase();
      res = res.filter(
        (r) =>
          r.title.toLowerCase().includes(q) ||
          r.desc.toLowerCase().includes(q) ||
          r.url.toLowerCase().includes(q) ||
          r.tags.some((t) => t.toLowerCase().includes(q))
      );
    }
    if (sortBy === "newest") res.sort((a, b) => b.createdAt - a.createdAt);
    else if (sortBy === "oldest") res.sort((a, b) => a.createdAt - b.createdAt);
    else if (sortBy === "title") res.sort((a, b) => a.title.localeCompare(b.title));
    return res;
  }, [records, filterCat, filterTag, search, sortBy]);

  const cats = Object.keys(CATEGORY_CONFIG);

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#F5F7FA",
        fontFamily: "'Noto Sans TC', sans-serif",
        color: "#1E293B",
      }}
    >
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+TC:wght@300;400;500;700&family=Space+Mono:wght@400;700&display=swap');
        * { box-sizing: border-box; margin: 0; padding: 0; }
        ::-webkit-scrollbar { width: 4px; }
        ::-webkit-scrollbar-track { background: #EEF0F4; }
        ::-webkit-scrollbar-thumb { background: #CBD5E1; border-radius: 2px; }
        .card { background: #FFFFFF; border: 1px solid #E8EDF3; border-radius: 12px; transition: all 0.2s; }
        .card:hover { border-color: #BFCBDA; transform: translateY(-1px); box-shadow: 0 4px 16px rgba(0,0,0,0.07); }
        .btn { cursor: pointer; border: none; border-radius: 8px; font-family: inherit; font-size: 13px; font-weight: 500; transition: all 0.15s; }
        .btn-primary { background: #3B82F6; color: white; padding: 8px 16px; }
        .btn-primary:hover { background: #2563EB; }
        .btn-ghost { background: transparent; color: #64748B; padding: 6px 10px; }
        .btn-ghost:hover { background: #F1F5F9; color: #1E293B; }
        .input { background: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 8px; color: #1E293B; padding: 9px 12px; font-family: inherit; font-size: 13px; outline: none; width: 100%; transition: border 0.15s; }
        .input:focus { border-color: #3B82F6; background: #fff; }
        .input::placeholder { color: #A0ADBF; }
        .tag { display: inline-flex; align-items: center; gap: 4px; padding: 2px 8px; border-radius: 20px; font-size: 11px; font-weight: 500; }
        .overlay { position: fixed; inset: 0; background: rgba(15,20,40,0.45); backdrop-filter: blur(4px); z-index: 50; display: flex; align-items: center; justify-content: center; }
        .chip { cursor: pointer; padding: 4px 12px; border-radius: 20px; font-size: 12px; border: 1px solid transparent; transition: all 0.15s; }
        .chip.active { border-color: #3B82F6; background: rgba(59,130,246,0.1); color: #2563EB; }
        .chip:not(.active) { border-color: #E2E8F0; color: #64748B; background: #fff; }
        .chip:hover:not(.active) { border-color: #BFCBDA; color: #334155; background: #F8FAFC; }
        .mono { font-family: 'Space Mono', monospace; }
        .toast { position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%); padding: 12px 20px; border-radius: 8px; font-size: 13px; font-weight: 500; z-index: 999; animation: fadeUp 0.3s ease; }
        @keyframes fadeUp { from { opacity:0; transform: translateX(-50%) translateY(8px); } to { opacity:1; transform: translateX(-50%) translateY(0); } }
        select option { background: #fff; color: #1E293B; }
      `}</style>

      {/* Header */}
      <div
        style={{
          borderBottom: "1px solid #E8EDF3",
          padding: "12px 24px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          position: "sticky",
          top: 0,
          background: "#fff",
          zIndex: 40,
          boxShadow: "0 1px 4px rgba(0,0,0,0.05)",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <div style={{ fontSize: 28 }}>🔗</div>
          <div>
            <div style={{ fontSize: 16, fontWeight: 700, color: "#1E293B" }}>連結資源庫</div>
            <div style={{ fontSize: 11, color: "#94A3B8" }}>
              已連接 Notion｜已儲存 {records.length} 份資料
            </div>
          </div>
        </div>

        <button className="btn btn-primary" onClick={openAdd}>
          <span style={{ fontSize: 16 }}>+</span> 新增連結
        </button>
      </div>

      <div style={{ maxWidth: 900, margin: "0 auto", padding: "20px 16px" }}>
        {/* Search bar */}
        <div style={{ display: "flex", gap: 8, marginBottom: 16 }}>
          <div style={{ position: "relative", flex: 1 }}>
            <span
              style={{
                position: "absolute",
                left: 12,
                top: "50%",
                transform: "translateY(-50%)",
                fontSize: 14,
                color: "#A0ADBF",
              }}
            >
              🔍
            </span>
            <input
              className="input"
              style={{ paddingLeft: 36 }}
              placeholder="搜尋標題、簡述、關鍵字..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          <select className="input" style={{ width: 110 }} value={sortBy} onChange={(e) => setSortBy(e.target.value)}>
            <option value="newest">最新優先</option>
            <option value="oldest">最舊優先</option>
            <option value="title">標題排序</option>
          </select>
        </div>

        {/* Category filter */}
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 10 }}>
          <span className={`chip ${filterCat === "all" ? "active" : ""}`} onClick={() => setFilterCat("all")}>
            全部
          </span>
          {cats.map((c) => (
            <span
              key={c}
              className={`chip ${filterCat === c ? "active" : ""}`}
              onClick={() => setFilterCat(filterCat === c ? "all" : c)}
            >
              {CATEGORY_CONFIG[c].icon} {c}
            </span>
          ))}
        </div>

        {/* Tag filter */}
        {allTags.length > 0 && (
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 16 }}>
            {allTags.map((t) => (
              <span
                key={t}
                className={`chip ${filterTag === t ? "active" : ""}`}
                style={{ fontSize: 11 }}
                onClick={() => setFilterTag(filterTag === t ? "" : t)}
              >
                #{t}
              </span>
            ))}
          </div>
        )}

        {/* Records */}
        {loading ? (
          <div style={{ textAlign: "center", color: "#94A3B8", padding: 60 }}>載入中…</div>
        ) : filtered.length === 0 ? (
          <div style={{ textAlign: "center", padding: 60, color: "#94A3B8" }}>
            <div style={{ fontSize: 32, marginBottom: 12 }}>📭</div>
            <div style={{ fontSize: 14 }}>
              {records.length === 0 ? "尚無資料，點擊右上角新增第一個連結" : "找不到符合條件的資料"}
            </div>
          </div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {filtered.map((rec) => {
              const cfg = CATEGORY_CONFIG[rec.category] || CATEGORY_CONFIG["其他"];
              return (
                <div key={rec.id} className="card" style={{ padding: "14px 16px" }}>
                  <div style={{ display: "flex", alignItems: "flex-start", gap: 12 }}>
                    <div
                      style={{
                        minWidth: 36,
                        height: 36,
                        borderRadius: 8,
                        background: cfg.bg,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        fontSize: 18,
                        marginTop: 1,
                      }}
                    >
                      {cfg.icon}
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
                        <span style={{ fontWeight: 600, fontSize: 14, color: "#1E293B" }}>{rec.title}</span>
                        <span
                          style={{
                            fontSize: 11,
                            padding: "1px 8px",
                            borderRadius: 20,
                            fontWeight: 500,
                            color: cfg.color,
                            background: cfg.bg,
                          }}
                        >
                          {rec.category}
                        </span>
                      </div>
                      {rec.desc && (
                        <div style={{ fontSize: 12, color: "#64748B", marginTop: 4, lineHeight: 1.6 }}>
                          {rec.desc}
                        </div>
                      )}
                      <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 6, flexWrap: "wrap" }}>
                        <a
                          href={rec.url}
                          target="_blank"
                          rel="noreferrer"
                          style={{
                            fontSize: 11,
                            color: "#3B82F6",
                            fontFamily: "Space Mono, monospace",
                            textDecoration: "none",
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                            whiteSpace: "nowrap",
                            maxWidth: 280,
                          }}
                          onMouseOver={(e) => (e.target.style.textDecoration = "underline")}
                          onMouseOut={(e) => (e.target.style.textDecoration = "none")}
                        >
                          {rec.url.length > 50 ? rec.url.slice(0, 50) + "…" : rec.url}
                        </a>
                        {rec.tags.map((t) => (
                          <span
                            key={t}
                            className="tag"
                            style={{ background: "#F1F5F9", color: "#64748B", cursor: "pointer" }}
                            onClick={() => setFilterTag(t)}
                          >
                            #{t}
                          </span>
                        ))}
                        <span
                          style={{
                            fontSize: 11,
                            color: "#94A3B8",
                            marginLeft: "auto",
                            display: "flex",
                            alignItems: "center",
                            gap: 8,
                          }}
                        >
                          {rec.source && <span style={{ color: "#3B82F6", fontSize: 11 }}>👤 {rec.source}</span>}
                          <span className="mono">{formatDate(rec.createdAt)}</span>
                        </span>
                      </div>
                    </div>
                    {/* Actions */}
                    <div style={{ display: "flex", gap: 4, marginTop: 2 }}>
                      {rec.notionUrl && (
                        <a
                          href={rec.notionUrl}
                          target="_blank"
                          rel="noreferrer"
                          className="btn btn-ghost"
                          style={{ fontSize: 15, padding: "4px 8px" }}
                          title="打開 Notion 頁面"
                        >
                          🔗
                        </a>
                      )}
                      <button
                        className="btn btn-ghost"
                        style={{ fontSize: 15, padding: "4px 8px" }}
                        title="複製連結"
                        onClick={() => copyCard(rec)}
                      >
                        {copied === rec.id ? "✓" : "📋"}
                      </button>
                      <button
                        className="btn btn-ghost"
                        style={{ fontSize: 15, padding: "4px 8px" }}
                        title="編輯"
                        onClick={() => openEdit(rec)}
                      >
                        ✏️
                      </button>
                      <button
                        className="btn btn-ghost"
                        style={{ fontSize: 15, padding: "4px 8px", color: "#EF4444" }}
                        title="刪除"
                        onClick={() => setDeleteConfirm(rec.id)}
                      >
                        🗑
                      </button>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Add/Edit Panel */}
      {panel && (
        <div
          className="overlay"
          onClick={(e) => {
            if (e.target === e.currentTarget) setPanel(false);
          }}
        >
          <div
            style={{
              background: "#FFFFFF",
              border: "1px solid #E8EDF3",
              borderRadius: 16,
              padding: 24,
              width: "90%",
              maxWidth: 520,
              maxHeight: "90vh",
              overflowY: "auto",
              boxShadow: "0 8px 32px rgba(0,0,0,0.1)",
            }}
          >
            <div style={{ fontWeight: 700, fontSize: 16, marginBottom: 6, color: "#1E293B" }}>
              {editId ? "編輯資料" : "新增連結"}
            </div>

            {!editId && (
              <>
                <div style={{ fontSize: 12, color: "#94A3B8", marginBottom: 14 }}>
                  將連結和說明一起貼上，AI 會自動整理
                </div>
                <div style={{ position: "relative" }}>
                  <textarea
                    className="input"
                    style={{ resize: "none", minHeight: 100, paddingBottom: 40, lineHeight: 1.7 }}
                    placeholder={
                      "直接貼上連結和說明，例如：\n\nhttps://docs.google.com/spreadsheets/d/...\n這是行銷部 Q2 廣告預算表，草稿階段，負責人小明"
                    }
                    value={inputRaw}
                    onChange={(e) => {
                      setInputRaw(e.target.value);
                      setAiDone(false);
                    }}
                  />
                  <button
                    className="btn btn-primary"
                    style={{
                      position: "absolute",
                      bottom: 10,
                      right: 10,
                      fontSize: 12,
                      padding: "5px 14px",
                      opacity: inputRaw.trim() ? 1 : 0.4,
                    }}
                    onClick={analyzeInput}
                    disabled={aiLoading || !inputRaw.trim()}
                  >
                    {aiLoading ? "✨ 分析中…" : "✨ AI 分析"}
                  </button>
                </div>
                {aiLoading && (
                  <div style={{ fontSize: 11, color: "#3B82F6", marginTop: 8, display: "flex", alignItems: "center", gap: 6 }}>
                    <span style={{ display: "inline-block", animation: "spin 1s linear infinite" }}>⏳</span> AI
                    正在提取連結、推測標題和簡述…
                  </div>
                )}
                {aiDone && (
                  <div style={{ fontSize: 11, color: "#10B981", marginTop: 8 }}>
                    ✓ 分析完成，請確認下方內容後儲存
                  </div>
                )}
                {aiDone && <div style={{ height: 1, background: "#E8EDF3", margin: "16px 0" }} />}
              </>
            )}

            {(aiDone || editId) && (
              <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
                <div>
                  <label style={{ fontSize: 12, color: "#64748B", display: "block", marginBottom: 6 }}>
                    連結網址
                  </label>
                  <input className="input" style={{ fontFamily: "Space Mono, monospace", fontSize: 12 }} value={inputUrl} onChange={(e) => setInputUrl(e.target.value)} />
                </div>
                <div>
                  <label style={{ fontSize: 12, color: "#64748B", display: "block", marginBottom: 6 }}>
                    標題
                  </label>
                  <input className="input" value={inputTitle} onChange={(e) => setInputTitle(e.target.value)} />
                </div>
                <div>
                  <label style={{ fontSize: 12, color: "#64748B", display: "block", marginBottom: 6 }}>
                    分類
                  </label>
                  <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                    {cats.map((c) => (
                      <span
                        key={c}
                        className={`chip ${inputCategory === c ? "active" : ""}`}
                        style={{ fontSize: 12 }}
                        onClick={() => setInputCategory(c)}
                      >
                        {CATEGORY_CONFIG[c].icon} {c}
                      </span>
                    ))}
                  </div>
                </div>
                <div>
                  <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 6 }}>
                    <label style={{ fontSize: 12, color: "#64748B" }}>文件簡述</label>
                    <button
                      className="btn btn-ghost"
                      style={{ fontSize: 11, padding: "3px 10px", border: "1px solid #E2E8F0", borderRadius: 20 }}
                      onClick={regenDesc}
                      disabled={aiLoading || !inputUrl}
                    >
                      {aiLoading ? "⏳" : "↺ 重新生成"}
                    </button>
                  </div>
                  <textarea className="input" style={{ resize: "vertical", minHeight: 72 }} value={inputDesc} onChange={(e) => setInputDesc(e.target.value)} />
                </div>
                <div>
                  <label style={{ fontSize: 12, color: "#64748B", display: "block", marginBottom: 6 }}>
                    來源（發話者）
                  </label>
                  <input className="input" placeholder="AI 自動識別，或手動填寫傳送此連結的人" value={inputSource} onChange={(e) => setInputSource(e.target.value)} />
                </div>
                <div>
                  <label style={{ fontSize: 12, color: "#64748B", display: "block", marginBottom: 6 }}>
                    標籤
                  </label>
                  {(() => {
                    const activeTags = inputTags
                      .split(/[,，]+/)
                      .map((t) => t.trim())
                      .filter(Boolean);
                    const existingSet = new Set(allTags.map((t) => t.toLowerCase()));
                    return (
                      <>
                        <div
                          style={{
                            display: "flex",
                            flexWrap: "wrap",
                            gap: 6,
                            minHeight: 36,
                            background: "#F8FAFC",
                            border: "1px solid #E2E8F0",
                            borderRadius: 8,
                            padding: "6px 10px",
                            alignItems: "center",
                          }}
                        >
                          {activeTags.map((t) => {
                            const isExisting = existingSet.has(t.toLowerCase());
                            return (
                              <span
                                key={t}
                                style={{
                                  display: "inline-flex",
                                  alignItems: "center",
                                  gap: 4,
                                  padding: "2px 8px",
                                  borderRadius: isExisting ? 4 : 20,
                                  fontSize: 12,
                                  fontWeight: 500,
                                  cursor: "default",
                                  background: isExisting ? "#DBEAFE" : "#F0FDF4",
                                  color: isExisting ? "#1D4ED8" : "#15803D",
                                  border: isExisting ? "1px solid #BFDBFE" : "1px dashed #86EFAC",
                                }}
                              >
                                {t}
                                <span
                                  style={{
                                    cursor: "pointer",
                                    fontSize: 11,
                                    opacity: 0.6,
                                    marginLeft: 2,
                                  }}
                                  onClick={() => setInputTags(activeTags.filter((x) => x !== t).join(", "))}
                                >
                                  ✕
                                </span>
                              </span>
                            );
                          })}
                          <input
                            style={{
                              border: "none",
                              outline: "none",
                              background: "transparent",
                              fontSize: 12,
                              color: "#1E293B",
                              minWidth: 80,
                              flex: 1,
                            }}
                            placeholder={activeTags.length ? "繼續輸入…" : "輸入標籤後按逗號或 Enter"}
                            onKeyDown={(e) => {
                              if (e.key === "," || e.key === "Enter") {
                                e.preventDefault();
                                const v = e.target.value.trim();
                                if (v && !activeTags.includes(v)) {
                                  setInputTags([...activeTags, v].join(", "));
                                }
                                e.target.value = "";
                              }
                            }}
                          />
                        </div>
                        {suggestedTags.length > 0 && (
                          <div style={{ marginTop: 8 }}>
                            <div style={{ fontSize: 11, color: "#94A3B8", marginBottom: 5 }}>AI 推薦（點擊加入）</div>
                            <div style={{ display: "flex", flexWrap: "wrap", gap: 5 }}>
                              {suggestedTags
                                .filter((t) => !activeTags.map((a) => a.toLowerCase()).includes(t.toLowerCase()))
                                .map((t) => {
                                  const isExisting = existingSet.has(t.toLowerCase());
                                  return (
                                    <span
                                      key={t}
                                      onClick={() => {
                                        if (!activeTags.includes(t)) setInputTags([...activeTags, t].join(", "));
                                      }}
                                      style={{
                                        cursor: "pointer",
                                        fontSize: 11,
                                        fontWeight: 500,
                                        padding: "2px 8px",
                                        borderRadius: isExisting ? 4 : 20,
                                        background: isExisting ? "#DBEAFE" : "transparent",
                                        color: isExisting ? "#1D4ED8" : "#15803D",
                                        border: isExisting ? "1px solid #BFDBFE" : "1px dashed #86EFAC",
                                        transition: "opacity 0.15s",
                                      }}
                                      title={isExisting ? "已存在的標籤" : "新標籤"}
                                    >
                                      {t}
                                    </span>
                                  );
                                })}
                            </div>
                          </div>
                        )}
                      </>
                    );
                  })()}
                </div>
                <div>
                  <label style={{ fontSize: 12, color: "#64748B", display: "block", marginBottom: 6 }}>
                    備註
                  </label>
                  <textarea
                    className="input"
                    style={{ resize: "vertical", minHeight: 60 }}
                    placeholder="其他說明..."
                    value={inputRemarks}
                    onChange={(e) => setInputRemarks(e.target.value)}
                  />
                </div>

                {/* 重複提示 */}
                {duplicateInfo && (
                  <div
                    style={{
                      background: "#FEF3C7",
                      border: "1px solid #FCD34D",
                      borderRadius: 8,
                      padding: 12,
                    }}
                  >
                    <div style={{ fontSize: 12, fontWeight: 600, color: "#92400E", marginBottom: 6 }}>
                      ✅ 已更新現有記錄
                    </div>
                    <div style={{ fontSize: 12, color: "#78350F", marginBottom: 8 }}>
                      此連結已存在於資料庫，已用新的分類、簡述和標籤進行更新。
                    </div>
                    <a
                      href={duplicateInfo.pageUrl}
                      target="_blank"
                      rel="noreferrer"
                      style={{
                        fontSize: 12,
                        color: "#D97706",
                        textDecoration: "none",
                        fontWeight: 500,
                      }}
                      onMouseOver={(e) => (e.target.style.textDecoration = "underline")}
                      onMouseOut={(e) => (e.target.style.textDecoration = "none")}
                    >
                      👉 打開 Notion 頁面查看
                    </a>
                  </div>
                )}
              </div>
            )}

            <div style={{ display: "flex", gap: 8, marginTop: 20, justifyContent: "flex-end" }}>
              <button className="btn btn-ghost" style={{ border: "1px solid #E2E8F0" }} onClick={() => setPanel(false)}>
                取消
              </button>
              {(aiDone || editId) && (
                <button
                  className="btn btn-primary"
                  onClick={handleSubmit}
                  disabled={!inputUrl.trim() || aiLoading}
                >
                  {editId ? "儲存變更" : "新增資料"}
                </button>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Delete confirm */}
      {deleteConfirm && (
        <div
          className="overlay"
          onClick={(e) => {
            if (e.target === e.currentTarget) setDeleteConfirm(null);
          }}
        >
          <div
            style={{
              background: "#FFFFFF",
              border: "1px solid #E8EDF3",
              borderRadius: 16,
              padding: 24,
              width: "88%",
              maxWidth: 360,
              textAlign: "center",
              boxShadow: "0 8px 32px rgba(0,0,0,0.1)",
            }}
          >
            <div style={{ fontSize: 28, marginBottom: 12 }}>🗑</div>
            <div style={{ fontWeight: 600, marginBottom: 8, color: "#1E293B" }}>確定要刪除？</div>
            <div style={{ fontSize: 13, color: "#94A3B8", marginBottom: 20 }}>此操作無法復原</div>
            <div style={{ display: "flex", gap: 8, justifyContent: "center" }}>
              <button className="btn btn-ghost" style={{ border: "1px solid #E2E8F0" }} onClick={() => setDeleteConfirm(null)}>
                取消
              </button>
              <button
                className="btn"
                style={{ background: "#EF4444", color: "white", padding: "8px 20px" }}
                onClick={() => handleDelete(deleteConfirm)}
              >
                確定刪除
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Toast */}
      {toast && (
        <div
          className="toast"
          style={{
            background: toast.type === "error" ? "#FEE2E2" : "#DBEAFE",
            color: toast.type === "error" ? "#DC2626" : "#1D4ED8",
            boxShadow: "0 4px 12px rgba(0,0,0,0.1)",
          }}
        >
          {toast.msg}
        </div>
      )}
    </div>
  );
}
