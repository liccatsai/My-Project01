# Google Sheets → Notion 版本里程碑同步
# 用法：.\sync-sheets-to-notion.ps1
# 排程：每天固定時間自動執行

param(
    [string]$GoogleDriveCsvUrl = '',  # Google Drive CSV 下載 URL
    [string]$CsvPath = 'version-data.csv'
)

# ⚠️ 重要：修改下方的 FILE_ID 為您自己的
# 格式：https://drive.google.com/uc?export=download&id=YOUR_FILE_ID
if ([string]::IsNullOrWhiteSpace($GoogleDriveCsvUrl)) {
    Write-Host "❌ 錯誤：未設定 Google Drive CSV URL" -ForegroundColor Red
    Write-Host "用法：.\sync-sheets-to-notion.ps1 -GoogleDriveCsvUrl 'https://drive.google.com/uc?export=download&id=YOUR_FILE_ID'" -ForegroundColor Yellow
    exit 1
}

$envFile = Join-Path $PSScriptRoot '.env'
$cfg = @{}
Get-Content $envFile -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { $cfg[$matches[1].Trim()] = $matches[2].Trim() }
}
$notionToken = $cfg['NOTION_TOKEN']

Write-Host "開始同步 Google Sheets → Notion..." -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────────────────────
# 步驟 1：讀取現有 Notion 資料庫內容
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "讀取 Notion 現有資料..."
$notionFilter = '{"page_size":20}'
$tmpNFilter = Join-Path $PSScriptRoot '.tmp_sync_filter.json'
$tmpNResponse = Join-Path $PSScriptRoot '.tmp_sync_response.json'
[System.IO.File]::WriteAllText($tmpNFilter, $notionFilter, [System.Text.Encoding]::UTF8)

curl.exe -s -X POST 'https://api.notion.com/v1/databases/de70adb016364bf7b606c9998ba71c6b/query' `
    -H "Authorization: Bearer $notionToken" `
    -H 'Notion-Version: 2022-06-28' `
    -H 'Content-Type: application/json' `
    --data-binary "@$tmpNFilter" `
    -o $tmpNResponse

Remove-Item $tmpNFilter -ErrorAction SilentlyContinue
$notionData = [System.IO.File]::ReadAllText($tmpNResponse, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
Remove-Item $tmpNResponse -ErrorAction SilentlyContinue

Write-Host "Notion 中已有 $($notionData.results.Count) 個版本"

# ──────────────────────────────────────────────────────────────────────────────
# 步驟 2：從 Google Drive 下載 CSV
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "從 Google Drive 下載 CSV 檔案..."
try {
    # 使用 -UserAgent 避免 Google 的防爬蟲機制
    Invoke-WebRequest -Uri $GoogleDriveCsvUrl -OutFile $CsvPath -UserAgent "Mozilla/5.0" -ErrorAction Stop
    Write-Host "✅ CSV 下載成功" -ForegroundColor Green
} catch {
    Write-Host "❌ 下載失敗：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# 步驟 3：讀取 CSV 檔案
# ──────────────────────────────────────────────────────────────────────────────
if (-not (Test-Path $CsvPath)) {
    Write-Host "❌ 找不到 $CsvPath" -ForegroundColor Red
    exit 1
}

Write-Host "讀取 CSV 檔案..."
$csvData = @(Import-Csv $CsvPath -Encoding UTF8)
Write-Host "載入 $($csvData.Count) 筆資料"

# ──────────────────────────────────────────────────────────────────────────────
# 步驟 4：轉換格式 並 更新 Notion
# ──────────────────────────────────────────────────────────────────────────────
$updateCount = 0
$skipCount = 0

foreach ($row in $csvData) {
    # Google Sheets 中的第 2 行是「版號」
    $version = $row.'版號'

    if ([string]::IsNullOrWhiteSpace($version)) { continue }

    # 版本用途（第 1 行）
    $purpose = $row.'版本用途'

    # 提取研發月份：從「研發合併」日期推算（第一個日期 = 該月）
    $devMergeStr = $row.'研發合併'
    $devMonth = if ($devMergeStr -match '(\d{4})\.(\d{2})') {
        "$($matches[1])-$($matches[2])-01"
    } else {
        $null
    }

    # 備註：暫時根據版本用途判斷
    $remark = switch -Regex ($purpose) {
        '老闆|AI|NPC' { '待確認' }
        'CB|OB' { '對外（待確認）' }
        '例行月版本' { '對內' }
        default { '對內' }
    }

    # 日期轉換（Google Sheets 格式 YYYY.MM.DD → Notion 格式 YYYY-MM-DD）
    $devMerge = if ($devMergeStr -match '(\d{4})\.(\d{2})\.(\d{2})') {
        "$($matches[1])-$($matches[2])-$($matches[3])"
    } else { $null }

    $submitQa = if ($row.'提交QA' -match '(\d{4})\.(\d{2})\.(\d{2})') {
        "$($matches[1])-$($matches[2])-$($matches[3])"
    } else { $null }

    $submitGtw = if ($row.'提交GTW' -match '(\d{4})\.(\d{2})\.(\d{2})') {
        "$($matches[1])-$($matches[2])-$($matches[3])"
    } else { $null }

    # 檢查該版本是否已在 Notion 中
    $existingPage = $notionData.results | Where-Object {
        $_.properties.'版號'.title[0].plain_text -eq $version
    }

    if ($existingPage) {
        # 更新現有頁面
        Write-Host "更新：v$version" -ForegroundColor Yellow

        $updateBody = @{
            properties = @{
                '版本用途' = @{ rich_text = @(@{ type = 'text'; text = @{ content = $purpose } }) }
                'date:研發月份:start' = $devMonth
                'date:研發月份:end' = $null
                'date:研發月份:is_datetime' = 0
                '備註' = $remark
                'date:研發合併:start' = $devMerge
                'date:研發合併:end' = $null
                'date:研發合併:is_datetime' = 0
                'date:提交QA:start' = $submitQa
                'date:提交QA:end' = $null
                'date:提交QA:is_datetime' = 0
                'date:提交GTW:start' = $submitGtw
                'date:提交GTW:end' = $null
                'date:提交GTW:is_datetime' = 0
            }
        } | ConvertTo-Json -Depth 10

        $pageId = $existingPage.id
        $tmpUpdateBody = Join-Path $PSScriptRoot ".tmp_update_$pageId.json"
        [System.IO.File]::WriteAllText($tmpUpdateBody, $updateBody, [System.Text.Encoding]::UTF8)

        curl.exe -s -X PATCH "https://api.notion.com/v1/pages/$pageId" `
            -H "Authorization: Bearer $notionToken" `
            -H 'Notion-Version: 2022-06-28' `
            -H 'Content-Type: application/json' `
            --data-binary "@$tmpUpdateBody" `
            -o $null

        Remove-Item $tmpUpdateBody -ErrorAction SilentlyContinue
        $updateCount++
    } else {
        # 新增頁面（通常不會執行，因為版本已預先建好）
        Write-Host "新增：v$version" -ForegroundColor Green

        $newPageBody = @{
            parent = @{ database_id = 'de70adb016364bf7b606c9998ba71c6b' }
            properties = @{
                '版號' = @{ title = @(@{ text = @{ content = $version } }) }
                '版本用途' = @{ rich_text = @(@{ type = 'text'; text = @{ content = $purpose } }) }
                'date:研發月份:start' = $devMonth
                'date:研發月份:end' = $null
                'date:研發月份:is_datetime' = 0
                '備註' = $remark
                'date:研發合併:start' = $devMerge
                'date:研發合併:end' = $null
                'date:研發合併:is_datetime' = 0
                'date:提交QA:start' = $submitQa
                'date:提交QA:end' = $null
                'date:提交QA:is_datetime' = 0
                'date:提交GTW:start' = $submitGtw
                'date:提交GTW:end' = $null
                'date:提交GTW:is_datetime' = 0
            }
        } | ConvertTo-Json -Depth 10

        $tmpNewPageBody = Join-Path $PSScriptRoot '.tmp_new_page.json'
        [System.IO.File]::WriteAllText($tmpNewPageBody, $newPageBody, [System.Text.Encoding]::UTF8)

        curl.exe -s -X POST 'https://api.notion.com/v1/pages' `
            -H "Authorization: Bearer $notionToken" `
            -H 'Notion-Version: 2022-06-28' `
            -H 'Content-Type: application/json' `
            --data-binary "@$tmpNewPageBody" `
            -o $null

        Remove-Item $tmpNewPageBody -ErrorAction SilentlyContinue
        $skipCount++
    }
}

Write-Host ""
Write-Host "✅ 同步完成！" -ForegroundColor Green
Write-Host "  更新版本：$updateCount"
Write-Host "  新增版本：$skipCount"
Write-Host ""
