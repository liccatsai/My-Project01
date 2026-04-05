# 會議記錄自動化 - 快速開始指南

## 3 步驟完成自動化

### 1️⃣ 複製會議記錄

從 Google Docs 或其他來源複製完整的會議記錄到剪貼板。

### 2️⃣ 開啟 PowerShell

在 `c:\Users\User\Documents\My Project01` 目錄中開啟 PowerShell：

```powershell
# 如果不在該目錄，先進入
cd "c:\Users\User\Documents\My Project01"
```

### 3️⃣ 執行自動化

**最簡單的方法** - 貼入會議記錄：

```powershell
$content = @"
2026年4月2日 | 活動模板例會_Kent
參與者: Mark、Licca、Lisa、Perry、柯進誠、吳彥霆

會議總結
...

待辦事項
【原創】
1. 提供雲端硬碟空間
2. 向路平確認網址
3. 向馬克回報
4. 追蹤下午會議
"@

.\process-meeting.ps1 -MeetingContent $content
```

## 預期輸出

```
🔍 解析會議記錄...
📅 日期: 2026-04-02
📋 會議: 活動模板例會_Kent
🏢 專案: 26便利
👥 參與者: Kent, 原創, 三叉, 怪獸
📝 待辦: 4 項

💾 寫入會議記錄索引...
✅ 會議索引: https://www.notion.so/xxxxx

💾 寫入 PM 待辦任務...
✅ 新增 4 項任務：
   ✅ 提供雲端硬碟空間給 Kent...
   ✅ 確認正式站網址並回饋 Kent
   ✅ 向馬克回報獎勵自動化...
   ✅ 追蹤下午「找不同」細節...

✨ 自動化完成！
```

## 會議記錄格式要求

為了讓自動化工具正確識別內容，請遵循以下格式：

```
[日期] | [會議名稱]
參與者: [名單]

[會議內容...]

待辦事項
【原創】
1. 任務1
2. 任務2
3. 任務3

【三叉】
1. 任務名稱

【Kent】
1. 任務名稱
```

## 日期格式支持

以下格式都可以：
- `2026年4月2日`
- `2026-04-02`
- `2026/04/02`

## 自動識別的欄位

| 欄位 | 自動識別 | 備註 |
|---|---|---|
| 日期 | ✅ | 從第一行提取 |
| 會議名稱 | ✅ | `\|` 之後的部分 |
| 參與者 | ✅ | 推斷單位歸屬 |
| 專案 | ✅ | 根據內容判斷（預設 26便利） |
| 會議類型 | ✅ | 根據關鍵字判斷（預設 例行週會） |
| 待辦項目 | ✅ | `【原創】` 標籤下的項目 |

## 常見問題

**Q: 如何只寫入會議索引，不建立任務？**
A: 如果待辦事項中沒有 `【原創】` 標籤，則不會建立任務。

**Q: 如何新增 Google Doc 連結？**
A: 使用 `-GoogleDocUrl` 參數：
```powershell
.\process-meeting.ps1 -MeetingContent $content -GoogleDocUrl "https://docs.google.com/document/d/..."
```

**Q: 能否自動化排程執行？**
A: 可以，使用 Windows Task Scheduler 或現有的 PowerShell 自動化流程整合。

---

需要幫助？檢查 `README-MEETING-AUTOMATION.md` 的詳細文檔。
