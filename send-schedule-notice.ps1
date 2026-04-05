# 26便利 排程通知產生器
# 判斷指定日期（預設今天）的排程節點，產出可貼至 LINE 群組的通知訊息
#
# 用法：
#   .\send-schedule-notice.ps1                       # 查今天
#   .\send-schedule-notice.ps1 -Date '2026-04-09'    # 查指定日期

param([string]$Date = '')

# 讀取 .env 設定
$envFile = Join-Path $PSScriptRoot '.env'
$cfg = @{}
Get-Content $envFile -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { $cfg[$matches[1].Trim()] = $matches[2].Trim() }
}
$notionToken = $cfg['NOTION_TOKEN']

$checkDate = if ($Date) {
    [datetime]::ParseExact($Date, 'yyyy-MM-dd', $null)
} else {
    (Get-Date).Date
}

# ── 台灣 2026 國定假日 ────────────────────────────────────────────────────────
$HOLIDAYS = @(
    '2026-01-01',                                                              # 元旦
    '2026-01-27','2026-01-28','2026-01-29','2026-01-30','2026-01-31',          # 春節
    '2026-02-02',                                                              # 春節補假
    '2026-02-28',                                                              # 和平紀念日
    '2026-04-03','2026-04-04','2026-04-05',                                    # 兒童節 / 清明
    '2026-05-01',                                                              # 勞動節
    '2026-06-19',                                                              # 端午節
    '2026-09-25','2026-09-26','2026-09-27',                                    # 中秋節
    '2026-10-09','2026-10-10'                                                  # 國慶日
)

function Test-IsHoliday([datetime]$d) {
    $dow = [int]$d.DayOfWeek   # 0=Sun, 6=Sat
    return ($dow -eq 0 -or $dow -eq 6) -or ($HOLIDAYS -contains $d.ToString('yyyy-MM-dd'))
}

function Get-WorkDay([datetime]$d) {
    while (Test-IsHoliday $d) { $d = $d.AddDays(1) }
    return $d
}

function Add-Month([int]$y, [int]$m, [int]$n) {
    $rm = $m + $n; $ry = $y
    while ($rm -gt 12) { $rm -= 12; $ry++ }
    return @($ry, $rm)
}

function Safe-Date([int]$y, [int]$m, [int]$d) {
    $maxD = [datetime]::DaysInMonth($y, $m)
    return [datetime]::new($y, $m, [Math]::Min($d, $maxD))
}

$WEEK_NAMES = @('日','一','二','三','四','五','六')
function Format-Date([datetime]$d) {
    $wn = $WEEK_NAMES[[int]$d.DayOfWeek]
    return "$($d.ToString('yyyy/MM/dd'))（週$wn）"
}

# ── 版本 ↔ 開發月份（從 Notion 讀取） ──────────────────────────────────────────
Write-Host '讀取版本里程碑資料...' -ForegroundColor Gray
$versionDbFilter = '{"page_size":20}'
$tmpVersionFilter = Join-Path $PSScriptRoot '.tmp_version_filter_notice.json'
$tmpVersionResponse = Join-Path $PSScriptRoot '.tmp_version_response_notice.json'
[System.IO.File]::WriteAllText($tmpVersionFilter, $versionDbFilter, [System.Text.Encoding]::UTF8)

curl.exe -s -X POST 'https://api.notion.com/v1/databases/de70adb016364bf7b606c9998ba71c6b/query' `
    -H "Authorization: Bearer $notionToken" `
    -H 'Notion-Version: 2022-06-28' `
    -H 'Content-Type: application/json' `
    --data-binary "@$tmpVersionFilter" `
    -o $tmpVersionResponse

Remove-Item $tmpVersionFilter -ErrorAction SilentlyContinue

$versionData = [System.IO.File]::ReadAllText($tmpVersionResponse, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
Remove-Item $tmpVersionResponse -ErrorAction SilentlyContinue

# 構建版本映射和備註
$VERSION_MAP = [ordered]@{}
$VERSION_NOTES = @{}

foreach ($versionPage in $versionData.results) {
    $ver = $versionPage.properties.'版號'.title[0].plain_text
    $yearMonth = $versionPage.properties.'研發月份'.date.start
    $purpose = $versionPage.properties.'版本用途'.rich_text[0].plain_text

    if ($yearMonth) {
        $vDate = [datetime]::ParseExact($yearMonth, 'yyyy-MM-dd', $null)
        $VERSION_MAP[$ver] = @($vDate.Year, $vDate.Month)

        # 提取特殊注意事項
        if ($purpose -match '老闆|AI|NPC|預計上線|CB|OB') {
            $VERSION_NOTES[$ver] = "⚠️ 特別注意：$purpose"
        }
    }
}

# ── 計算版本完整排程 ──────────────────────────────────────────────────────────
function Get-VersionSchedule([string]$ver) {
    if (-not $VERSION_MAP.Contains($ver)) { return $null }
    $ym = $VERSION_MAP[$ver]; $mY = $ym[0]; $mM = $ym[1]
    $m1 = Add-Month $mY $mM 1; $m1Y = $m1[0]; $m1M = $m1[1]
    $m2 = Add-Month $mY $mM 2; $m2Y = $m2[0]; $m2M = $m2[1]

    # 階段（月曆日期為範圍基準，工作日順延日期用於通知觸發）
    $phases = @(
        [PSCustomObject]@{
            Name='功能開發（不合併）'; Who='三叉、唯晶'
            CalStart=Safe-Date $mY $mM 1;  CalEnd=Safe-Date $mY $mM 8
            WdStart=Get-WorkDay(Safe-Date $mY $mM 1); WdEnd=Get-WorkDay(Safe-Date $mY $mM 8)
        }
        [PSCustomObject]@{
            Name='三叉合併至 CSP'; Who='三叉開發'
            CalStart=Safe-Date $mY $mM 9;  CalEnd=Safe-Date $mY $mM 16
            WdStart=Get-WorkDay(Safe-Date $mY $mM 9); WdEnd=Get-WorkDay(Safe-Date $mY $mM 16)
        }
        [PSCustomObject]@{
            Name='唯晶合併至 CSP'; Who='唯晶開發'
            CalStart=Safe-Date $mY $mM 17; CalEnd=Safe-Date $mY $mM 24
            WdStart=Get-WorkDay(Safe-Date $mY $mM 17); WdEnd=Get-WorkDay(Safe-Date $mY $mM 24)
        }
        [PSCustomObject]@{
            Name='三叉包版'; Who='三叉開發'
            CalStart=Safe-Date $mY $mM 25; CalEnd=Safe-Date $mY $mM 30
            WdStart=Get-WorkDay(Safe-Date $mY $mM 25); WdEnd=Get-WorkDay(Safe-Date $mY $mM 30)
        }
    )

    # 里程碑（工作日順延）
    $milestones = @(
        [PSCustomObject]@{ Date=Get-WorkDay(Safe-Date $mY  $mM  26); Label='PM 提供驗測清單給 QA';        Who='PM → 異起 QA' }
        [PSCustomObject]@{ Date=Get-WorkDay(Safe-Date $m1Y $m1M 6);  Label='三叉提供 TEST APK/IPA 給 QA'; Who='三叉開發 → 異起 QA' }
        [PSCustomObject]@{ Date=Get-WorkDay(Safe-Date $m1Y $m1M 9);  Label='驗測文件修正版';               Who='異起 QA' }
        [PSCustomObject]@{ Date=Get-WorkDay(Safe-Date $m2Y $m2M 6);  Label='三叉提供營運版本';              Who='三叉開發 → 營運' }
    )

    return [PSCustomObject]@{ Version=$ver; Phases=$phases; Milestones=$milestones }
}

# ── 主邏輯 ────────────────────────────────────────────────────────────────────
$allMsgs = @()

foreach ($kv in $VERSION_MAP.GetEnumerator()) {
    $ver = $kv.Key
    $sch = Get-VersionSchedule $ver

    # 找活躍階段（月曆日期範圍）
    $activePhase = $sch.Phases | Where-Object { $checkDate -ge $_.CalStart -and $checkDate -le $_.CalEnd }
    # 找今日里程碑
    $todayMs = $sch.Milestones | Where-Object { $_.Date.Date -eq $checkDate.Date }

    if (-not $activePhase -and $todayMs.Count -eq 0) { continue }

    # 收集後續節點（用於「後續節點」欄位）
    $allFuture = @()
    if ($activePhase -and $activePhase.WdEnd -gt $checkDate) {
        $allFuture += [PSCustomObject]@{ Date=$activePhase.WdEnd; Label="$($activePhase.Name) 截止" }
    }
    foreach ($p in $sch.Phases) {
        if ($p.WdStart -gt $checkDate -and (-not $activePhase -or $p.Name -ne $activePhase.Name)) {
            $allFuture += [PSCustomObject]@{ Date=$p.WdStart; Label="$($p.Name) 開始" }
        }
    }
    foreach ($ms in $sch.Milestones) {
        if ($ms.Date -gt $checkDate) {
            $allFuture += [PSCustomObject]@{ Date=$ms.Date; Label=$ms.Label }
        }
    }
    $upcoming = $allFuture | Sort-Object Date | Select-Object -First 4

    # ── 組裝訊息 ──
    $msgLines = @()
    $msgLines += "【26便利 v$ver 排程提醒】"
    $msgLines += "📅 $(Format-Date $checkDate)"
    $msgLines += ''

    # 今日里程碑
    foreach ($ms in $todayMs) {
        $msgLines += "📌 今日節點：$($ms.Label)"
        $msgLines += "👥 相關人員：$($ms.Who)"
        $msgLines += ''
    }

    # 階段狀態
    if ($activePhase) {
        $isStart = ($checkDate.Date -eq $activePhase.WdStart.Date)
        $isEnd   = ($checkDate.Date -eq $activePhase.WdEnd.Date)
        $remaining = ([int]($activePhase.WdEnd - $checkDate).TotalDays)
        $endStr  = "$(Format-Date $activePhase.WdEnd)"

        if ($isEnd) {
            $msgLines += "⛔ 今日截止：$($activePhase.Name)"
        } elseif ($isStart) {
            $msgLines += "▶ 今日起：$($activePhase.Name)"
            $msgLines += "   截止：$endStr（共 $remaining 天）"
        } else {
            $msgLines += "📍 目前階段：$($activePhase.Name)"
            $msgLines += "   截止：$endStr（剩餘 $remaining 天）"
        }
        $msgLines += "👥 相關人員：$($activePhase.Who)"
        $msgLines += ''
    }

    # 特殊注意
    if ($VERSION_NOTES[$ver]) {
        $msgLines += $VERSION_NOTES[$ver]
        $msgLines += ''
    }

    # 後續節點
    if ($upcoming.Count -gt 0) {
        $msgLines += '⏭ 後續節點：'
        foreach ($u in $upcoming) {
            $msgLines += "  • $(Format-Date $u.Date)　$($u.Label)"
        }
    }

    $allMsgs += ($msgLines -join "`n").TrimEnd()
}

# ── 輸出 ──────────────────────────────────────────────────────────────────────
if ($allMsgs.Count -eq 0) {
    Write-Host ''
    Write-Host "[ $(Format-Date $checkDate) ] 今日無排程節點" -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}

$separator = "`n`n─────────────────────────────────`n`n"
$output = $allMsgs -join $separator

Write-Host ''
Write-Host $output -ForegroundColor Cyan
Write-Host ''

try {
    $output | Set-Clipboard
    Write-Host '（已複製至剪貼板，可直接貼至 LINE 群組）' -ForegroundColor Green
} catch {
    Write-Host '（請手動複製以上內容貼至 LINE 群組）' -ForegroundColor Yellow
}
Write-Host ''
