# 🔗 連結資源庫

自動分類、智能去重的連結管理工具。支持 AI 智能分析，一鍵存儲到 Notion。

## ✨ 主要功能

- 📝 **AI 智能分析**：複製連結 + 說明 → AI 自動提取標題、分類、簡述、標籤
- 🔄 **完全自動化**：無需手動填寫欄位，所有內容自動生成
- 🚫 **智能去重**：檢測相同 URL，自動更新現有記錄，並顯示通知
- ☁️ **Notion 整合**：直接保存到 Notion 資料庫，支持多電腦訪問
- 💾 **本地備份**：同時保存本地副本（離線可用）
- 🔍 **強大檢索**：按分類、標籤、關鍵字搜尋

## 🚀 快速開始

### 1️⃣ 本地開發（可選）

```bash
# 安裝依賴
npm install

# 啟動開發伺服器
npm run dev
```

訪問 `http://localhost:3000`

### 2️⃣ 部署到 Vercel（推薦）

#### 前置準備

1. **取得 Claude API Key**
   - 訪問 https://console.anthropic.com/
   - 複製 API Key

2. **取得 Notion Integration Token**
   - 訪問 https://www.notion.so/my-integrations
   - 點 **「+ 新增整合」**
   - 名稱：`Link Manager`
   - 複製 **Internal Integration Token**
   - 打開資料庫「🔗 連接資源庫」
   - 右上角「…」→ **「連線」** → 搜尋 `Link Manager` → 允許

3. **Notion 資料庫 ID**
   - 資料庫 ID：`f9c413fb8fe347168ef0207dcfaa5cbb`
   - （已預設，無需更改）

#### 部署步驟

##### 方法 A：使用 GitHub + Vercel（推薦）

1. **建立 GitHub 倉庫**
   ```bash
   # 在項目根目錄
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/link-manager.git
   git push -u origin main
   ```

2. **連接 Vercel**
   - 訪問 https://vercel.com
   - 點 **「New Project」**
   - 選擇 GitHub 上的 `link-manager` 倉庫
   - 點 **「Import」**

3. **配置環境變數**
   - 在 Vercel 控制台找到 **「Settings」** → **「Environment Variables」**
   - 添加以下變數：
     ```
     ANTHROPIC_API_KEY=sk-ant-...（你的 Claude API Key）
     NOTION_TOKEN=ntn_...（你的 Notion Token）
     NOTION_DATABASE_ID=f9c413fb8fe347168ef0207dcfaa5cbb
     ```
   - 點 **「Save」**

4. **部署**
   - 返回 **「Deployments」** 標籤
   - 點最新的部署中的 **「Redeploy」**
   - 等待部署完成
   - 訪問提供的 URL（如 `https://link-manager.vercel.app`）

##### 方法 B：使用 Vercel CLI

```bash
# 安裝 Vercel CLI
npm install -g vercel

# 登入
vercel login

# 部署
vercel
# 按提示填寫項目名稱、環境變數等
```

## 📖 使用指南

### 添加新連結

1. 點擊右上角 **「+ 新增連結」**
2. 貼入連結 + 說明（如 `https://... 這是行銷部預算表，草稿階段，小明提供`）
3. 點 **「✨ AI 分析」**
4. AI 自動填寫：標題、分類、簡述、標籤、提供者
5. 確認無誤後，點 **「新增資料」**
6. 連結自動存到 Notion + 本地

### 重複連結

如果連結已存在（相同 URL）：
- 系統自動**更新現有記錄**
- 新的分類、簡述、標籤會覆蓋舊內容
- 你會看到通知：**「✅ 已更新現有記錄」**
- 可點擊連結直接打開 Notion 頁面

### 搜尋 & 篩選

- **全文搜尋**：標題、簡述、連結、標籤都支持
- **分類篩選**：點擊分類圖標（美術、排程、文件等）
- **標籤篩選**：點擊 `#標籤`
- **排序**：最新優先 / 最舊優先 / 標題排序

### 編輯 & 刪除

- **編輯**：點卡片上的 **「✏️」** 按鈕
- **刪除**：點 **「🗑」** 按鈕
- **打開 Notion**：點 **「🔗」** 按鈕（若已同步到 Notion）

## 🔧 環境變數配置

| 變數 | 說明 | 範例 |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude API Key | `sk-ant-...` |
| `NOTION_TOKEN` | Notion Integration Token | `ntn_...` |
| `NOTION_DATABASE_ID` | 資料庫 ID | `f9c413fb8fe347168ef0207dcfaa5cbb` |

## 📊 Notion 資料庫結構

**資料庫名稱**：🔗 連接資源庫

### 欄位說明

| 欄位 | 類型 | 說明 |
|---|---|---|
| 連結名稱 | Title | AI 自動生成（5-20 字） |
| URL | URL | 原始連結（去重鍵） |
| 分類 | Select | 美術、排程、會議紀錄、文件、試算表、簡報、資料夾、其他 |
| 簡述 | Text | 「[類型] — [用途],[狀態]」格式 |
| 來源渠道 | Select | 手動粘貼、郵件轉發、Google Chat、LINE、其他 |
| 提供者 | Text | 發送者名稱 |
| 標籤 | Multi-select | 便於篩選和分組 |
| 備註 | Text | 額外說明 |
| 驗證狀態 | Select | 待驗證、已驗證、已過期 |

## 🐛 故障排除

### ❌ "Claude API key not configured"

1. 檢查環境變數中是否設定 `ANTHROPIC_API_KEY`
2. 確認 API Key 有效（從 https://console.anthropic.com/ 複製）
3. 若使用 Vercel，確認已在 **Environment Variables** 中添加

### ❌ "Notion credentials not configured"

1. 檢查 `NOTION_TOKEN` 和 `NOTION_DATABASE_ID`
2. 確認 Notion Token 有效（從 https://www.notion.so/my-integrations 複製）
3. 確認已給 Integration 授權訪問資料庫

### ❌ "Notion API error: unauthorized"

1. 打開 Notion 資料庫 **「🔗 連接資源庫」**
2. 右上角 **「…」** → **「連線」**
3. 搜尋 **「Link Manager」** 整合
4. 點 **「允許」** 授權

### ❌ 無法在 Vercel 上訪問（404）

1. 確認部署已完成（檢查 **Deployments** 標籤）
2. 等待 1-2 分鐘後重新訪問
3. 若仍然失敗，點 **「Redeploy」** 重新部署

## 🎯 最佳實踐

- 📌 **提供充足上下文**：連結 + 簡短說明能獲得更好的 AI 分析
- 🏷️ **一致的標籤**：使用相同的標籤便於後續檢索
- ✔️ **定期驗證**：檢查「待驗證」的連結，更新狀態
- 🔍 **充分利用搜尋**：善用全文搜尋和標籤篩選

## 📝 更新日誌

### v1.0.0 (2026-04-05)
- ✨ 首次發佈
- 支持 AI 智能分析
- 支持 Notion 整合和去重
- 支持本地備份和多電腦訪問

## 📞 問題回報

如有任何問題，請提出。

---

**👉 [馬上開始使用](https://link-manager.vercel.app)**
