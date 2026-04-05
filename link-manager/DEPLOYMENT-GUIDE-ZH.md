# 📦 Vercel 部署指南（繁體中文）

一步步指導你在 Vercel 上部署**連結資源庫**。

## 🎯 目標

部署完成後，你將擁有：
- ✅ 網址：`https://你的應用名稱.vercel.app`
- ✅ 任何電腦、任何瀏覽器都能訪問
- ✅ AI 自動分析連結 + 自動存到 Notion
- ✅ 支持多人訪問

---

## 📋 前置準備（3 樣東西）

### 1️⃣ Claude API Key

**怎麼取得？**

1. 訪問 https://console.anthropic.com/
2. 登入（無帳號則註冊）
3. 左側導航找 **「API Keys」**
4. 點 **「Create Key」**
5. 複製祕密金鑰（開頭是 `sk-ant-`）
6. **保存好！稍後需要**

**驗證是否有效**
```
開頭：sk-ant-
長度：約 100+ 字符
```

---

### 2️⃣ Notion Integration Token

**怎麼取得？**

1. 訪問 https://www.notion.so/my-integrations
2. 點 **「+ 新增整合」**
3. 填寫名稱：`Link Manager`
4. 點 **「送出」**
5. 複製 **Internal Integration Token**（開頭是 `ntn_`）
6. **保存好！稍後需要**

**關鍵步驟：授權給資料庫**

1. 打開 Notion 資料庫 **「🔗 連接資源庫」**
2. 右上角點 **「…」**（更多選項）
3. 選 **「新增連線」** 或 **「連線」**
4. 搜尋 **「Link Manager」**
5. 點 **「允許」** 授權

⚠️ **重要**：如果沒有授權，Notion API 會拒絕存儲！

---

### 3️⃣ Notion 資料庫 ID

**已預設**（無需操作）
```
NOTION_DATABASE_ID=f9c413fb8fe347168ef0207dcfaa5cbb
```

---

## 🚀 部署方式（選一種）

### 方式 A：使用 GitHub + Vercel（推薦，最簡單）

**✨ 優點**：
- 無需本地操作
- 自動部署更新
- 支持團隊協作

**步驟**

#### Step 1: 建立 GitHub 倉庫

1. 訪問 https://github.com/new
2. 填寫倉庫名稱：`link-manager`
3. 選 **「Public」**（推薦，便於訪問）
4. 點 **「Create repository」**

複製倉庫 URL（如 `https://github.com/你的用戶名/link-manager.git`）

#### Step 2: 上傳代碼到 GitHub

在 `link-manager` 資料夾中打開 **PowerShell** 或 **命令提示字元**：

```powershell
# 初始化 Git 倉庫
git init

# 添加所有文件
git add .

# 建立首次提交
git commit -m "Initial commit: link manager setup"

# 重命名分支為 main（如需要）
git branch -M main

# 連接遠程倉庫（替換為你的倉庫 URL）
git remote add origin https://github.com/你的用戶名/link-manager.git

# 推送到 GitHub
git push -u origin main
```

✅ 檢查：訪問 https://github.com/你的用戶名/link-manager，應能看到所有文件

#### Step 3: 連接 Vercel

1. 訪問 https://vercel.com
2. 點 **「Sign Up」** 或 **「Log In」**
3. 選 **「Continue with GitHub」**
4. 授權 Vercel 訪問你的 GitHub 帳號
5. 點 **「New Project」**
6. 搜尋 **「link-manager」** 倉庫
7. 點 **「Import」**

#### Step 4: 配置環境變數

1. **Project Name**：保持預設（`link-manager`）
2. **Framework Preset**：應自動選中 **「Next.js」**
3. 向下滾到 **「Environment Variables」**
4. 添加以下 3 個變數：

| Name | Value |
|---|---|
| `ANTHROPIC_API_KEY` | `sk-ant-...`（你的 Claude API Key） |
| `NOTION_TOKEN` | `ntn_...`（你的 Notion Token） |
| `NOTION_DATABASE_ID` | `f9c413fb8fe347168ef0207dcfaa5cbb` |

5. 點 **「Deploy」**

#### Step 5: 等待部署完成

- 頁面會顯示進度（Building... Deploying...）
- 約 1-2 分鐘後顯示 **「Congratulations!」**
- 複製部署 URL（如 `https://link-manager-abc123.vercel.app`）

✅ **完成！** 訪問該 URL 即可使用

---

### 方式 B：使用 Vercel CLI（快速）

**前置**：
- 已安裝 Node.js
- 在 `link-manager` 資料夾打開終端

**步驟**

```bash
# 1. 安裝 Vercel CLI
npm install -g vercel

# 2. 登入（會自動打開瀏覽器）
vercel login

# 3. 部署
vercel

# 依提示填寫：
# - Project name: link-manager
# - Directory to deploy: .（點，表示當前目錄）
# - Environment variables: 
#   ANTHROPIC_API_KEY=sk-ant-...
#   NOTION_TOKEN=ntn_...
#   NOTION_DATABASE_ID=f9c413fb8fe347168ef0207dcfaa5cbb

# 4. 等待部署完成，複製 URL
```

---

## ✅ 驗證部署成功

### 檢查清單

- [ ] 訪問部署 URL 能打開網頁（不是 404）
- [ ] 頁面顯示「連結資源庫」標題
- [ ] 點 **「+ 新增連結」** 能打開對話框
- [ ] 測試 AI 分析（貼一個連結試試）
- [ ] 測試存到 Notion（點「新增資料」後檢查 Notion）

### 測試連結

```
貼入此文本到輸入框：

https://www.notion.so/f9c413fb8fe347168ef0207dcfaa5cbb
這是連結資源庫的主資料庫，用於存儲團隊分享的所有資源

然後點「✨ AI 分析」，應自動填寫所有欄位。
```

### 常見問題排查

#### ❌ 頁面顯示「503 Service Unavailable」

**原因**：構建失敗或尚未完成

**解決**：
1. 回到 Vercel 控制台
2. 點 **「Deployments」** 標籤
3. 檢查最新部署的狀態
4. 若失敗，點 **「Redeploy」** 重新部署

#### ❌ 點「AI 分析」後出現「Claude API key not configured」

**原因**：環境變數未正確設定

**解決**：
1. 回到 Vercel 項目設定
2. 點 **「Settings」** → **「Environment Variables」**
3. 確認 `ANTHROPIC_API_KEY` 存在且正確
4. 點 **「Redeploy」** 重新部署

#### ❌ 連結存不了，顯示「Notion credentials not configured」

**原因**：Notion Token 或資料庫 ID 錯誤，或未授權

**解決**：
1. 檢查 Vercel 環境變數
2. 確認 Notion Token 正確（`ntn_` 開頭）
3. **重點**：打開 Notion 資料庫 → 授權 **「Link Manager」** 整合（見前置準備步驟 2）
4. 點 **「Redeploy」** 重新部署

---

## 📱 在公司電腦訪問

部署後，任何電腦都能訪問：

1. 打開瀏覽器（Chrome、Safari、Edge 等）
2. 輸入 URL：`https://你的應用名稱.vercel.app`
3. 登入（若需要）
4. 開始新增連結

---

## 🔄 更新代碼

若日後修改代碼：

**使用 GitHub 方式**
```bash
cd link-manager
git add .
git commit -m "Update message"
git push origin main
# Vercel 自動部署
```

**使用 CLI 方式**
```bash
vercel --prod
```

---

## 🚨 安全提示

- 🔐 **不要分享** `ANTHROPIC_API_KEY` 和 `NOTION_TOKEN`
- 🔐 不要在代碼中寫死密鑰（使用環境變數）
- 🔐 倉庫設為 **Private**（若涉及公司敏感信息）

---

## 📊 成本

- **Claude API**：按使用量計費（建議設定額度警告）
- **Notion**：已有資料庫，無額外成本
- **Vercel**：免費層足夠（最多 100 GB 流量/月）

---

## 💬 需要幫助？

1. 檢查上述「常見問題排查」
2. 查看 Vercel Logs（Deployments → 點部署 → Logs）
3. 查看 Browser Console（F12 → Console 標籤，看有無紅色錯誤）

---

**🎉 恭喜！你已成功部署連結資源庫！**

現在可以：
- 📱 在任何電腦添加連結
- 🤖 讓 AI 自動分類
- 💾 直接存到 Notion
- 🔍 隨時檢索和共享

祝使用愉快！
