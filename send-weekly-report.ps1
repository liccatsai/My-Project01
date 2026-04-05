param([string]$Start = '', [string]$End = '')

$envFile = Join-Path $PSScriptRoot '.env'
$cfg = @{}
Get-Content $envFile -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { $cfg[$matches[1].Trim()] = $matches[2].Trim() }
}
$notionToken = $cfg['NOTION_TOKEN']
$gmail       = $cfg['GMAIL_ADDRESS']
$gmailPass   = $cfg['GMAIL_APP_PASSWORD']

$today = Get-Date
if ($Start -ne '' -and $End -ne '') {
    $weekStart = [datetime]::ParseExact($Start, 'MM/dd', $null)
    $weekEnd   = [datetime]::ParseExact($End,   'MM/dd', $null)
    $weekStart = $weekStart.AddYears($today.Year - $weekStart.Year)
    $weekEnd   = $weekEnd.AddYears($today.Year - $weekEnd.Year)
} else {
    $dow = [int]$today.DayOfWeek
    $mondayOffset = if ($dow -eq 0) { -6 } else { 1 - $dow }
    $weekStart = $today.AddDays($mondayOffset)
    $weekEnd   = $weekStart.AddDays(4)
}

# 計算本月第幾週（以週一為準，月份第一個週一為W1）
$firstDayOfMonth = (Get-Date $weekStart -Day 1)
$firstMonday = $firstDayOfMonth
while ([int]$firstMonday.DayOfWeek -ne 1) { $firstMonday = $firstMonday.AddDays(1) }
$weekNum  = [math]::Ceiling(($weekStart - $firstMonday).TotalDays / 7) + 1
$startStr = $weekStart.ToString('MM/dd')
$endStr   = $weekEnd.ToString('MM/dd')
$title    = "$($weekStart.ToString('yyyy/MM')) W$weekNum 週報（$startStr－$endStr）"
Write-Host "Period: $startStr ~ $endStr"
Write-Host 'Loading Notion tasks...'

$filterBody = '{"page_size":100}'
$tmpFilter   = Join-Path $PSScriptRoot '.tmp_filter.json'
$tmpResponse = Join-Path $PSScriptRoot '.tmp_response.json'
[System.IO.File]::WriteAllText($tmpFilter, $filterBody, [System.Text.Encoding]::UTF8)
curl.exe -s -X POST 'https://api.notion.com/v1/databases/dd5ad18a-33d0-4190-ae85-f365d6024fb5/query' `
    -H "Authorization: Bearer $notionToken" -H 'Notion-Version: 2022-06-28' `
    -H 'Content-Type: application/json' --data-binary "@$tmpFilter" -o $tmpResponse
Remove-Item $tmpFilter -ErrorAction SilentlyContinue
$data  = [System.IO.File]::ReadAllText($tmpResponse, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
Remove-Item $tmpResponse -ErrorAction SilentlyContinue
$tasks = $data.results
Write-Host "Tasks: $($tasks.Count)"

$cats = @('版本開發與測試','需求對接與調整','技術障礙排除','內部協調與會議','行政與法務事務')
$p26 = @{}; $p99 = @{}; $other = @{}
foreach ($c in $cats) { $p26[$c] = @(); $p99[$c] = @(); $other[$c] = @() }

# 下週計畫容器
$next26 = @(); $next99 = @()
# 風險容器
$risks = @()

foreach ($t in $tasks) {
    $name    = $t.properties.'任務名稱'.title[0].plain_text
    $proj    = $t.properties.'專案'.select.name
    $status  = $t.properties.'狀態'.select.name
    $type    = $t.properties.'類型'.select.name
    $desc    = $t.properties.'說明'.rich_text[0].plain_text
    $note    = $t.properties.'備註/阻礙說明'.rich_text[0].plain_text
    $updated = $t.properties.'更新日期'.date.start

    # 本週工作摘要：已完成須在本週內
    if ($status -eq '已完成') {
        if (-not $updated) { continue }
        $updDate = [datetime]$updated
        if ($updDate -lt $weekStart -or $updDate -gt $weekEnd) { continue }
    }

    $summary = if ($desc) { $desc } elseif ($note) { $note } else { $status }
    if ($summary.Length -gt 70) { $summary = $summary.Substring(0, 70) + '...' }
    $line = "[$status] $name：$summary"

    $cat = switch ($type) {
        '開發協作'   { '版本開發與測試' }
        '跨部門協作' { '需求對接與調整' }
        '風險/決策'  { '技術障礙排除'   }
        '會議'       { '內部協調與會議' }
        '文件/報告'  { '行政與法務事務' }
        default      { '版本開發與測試' }
    }

    if ($proj -eq '26便利')     { $p26[$cat]   += $line }
    elseif ($proj -eq '99便利') { $p99[$cat]   += $line }
    else                         { $other[$cat] += $line }

    # 下週計畫：進行中／追蹤中任務
    if ($status -eq '進行中' -or $status -eq '追蹤中') {
        $nextLine = "$name：$summary"
        if ($proj -eq '26便利')     { $next26 += $nextLine }
        elseif ($proj -eq '99便利') { $next99 += $nextLine }
    }

    # 本週風險：阻礙 or 風險/決策 type or 待確認有備註
    if ($status -eq '阻礙' -or $type -eq '風險/決策' -or ($status -eq '待確認' -and $note)) {
        $riskDesc = if ($note) { $note } elseif ($desc) { $desc } else { $status }
        if ($riskDesc.Length -gt 70) { $riskDesc = $riskDesc.Substring(0, 70) + '...' }
        $riskStatus = if ($status -eq '阻礙') { '阻礙' } elseif ($status -eq '已完成') { '已完成' } else { '待處理' }
        $risks += "$riskStatus－$name：$riskDesc（$proj）"
    }
}

$cn    = @('一','二','三','四','五')
$lines = @($title, '', '## 本週工作摘要', '### 【26便利】')
$i = 0
foreach ($c in $cats[0..3]) {
    if ($p26[$c].Count -gt 0) {
        $lines += "#### $($cn[$i])、$c"
        $n = 1; foreach ($item in $p26[$c]) { $lines += "$n. $item"; $n++ }
    }; $i++
}
$lines += '### 【99便利】'; $i = 0
foreach ($c in $cats[0..1]) {
    if ($p99[$c].Count -gt 0) {
        $lines += "#### $($cn[$i])、$c"
        $n = 1; foreach ($item in $p99[$c]) { $lines += "$n. $item"; $n++ }
    }; $i++
}
if ($other['行政與法務事務'].Count -gt 0) {
    $lines += '### 【其他】'; $lines += '#### 一、行政與法務事務'
    $n = 1; foreach ($item in $other['行政與法務事務']) { $lines += "$n. $item"; $n++ }
}

$lines += @('', '## 下週計畫', '### 【26便利】')
if ($next26.Count -gt 0) {
    $n = 1; foreach ($item in $next26) { $lines += "$n. $item"; $n++ }
} else { $lines += '1. （無進行中任務）' }
$lines += '### 【99便利】'
if ($next99.Count -gt 0) {
    $n = 1; foreach ($item in $next99) { $lines += "$n. $item"; $n++ }
} else { $lines += '1. （無進行中任務）' }

$lines += @('', '## 本週風險／問題')
if ($risks.Count -gt 0) {
    $n = 1; foreach ($item in $risks) { $lines += "$n. $item"; $n++ }
} else { $lines += '1. 無風險事項' }

$report = $lines -join "`n"
Write-Host $report

Write-Host 'Sending Email...'
Send-MailMessage -From $gmail -To $gmail -Subject $title -Body $report -Encoding UTF8 `
    -SmtpServer 'smtp.gmail.com' -Port 587 -UseSsl `
    -Credential (New-Object System.Management.Automation.PSCredential($gmail, (ConvertTo-SecureString $gmailPass -AsPlainText -Force)))
Write-Host 'Email sent!' -ForegroundColor Green

Write-Host 'Writing to Notion...'
function New-H1($t)  { @{ object='block'; type='heading_1'; heading_1=@{ rich_text=@(@{ type='text'; text=@{ content=$t } }) } } }
function New-H2($t)  { @{ object='block'; type='heading_2'; heading_2=@{ rich_text=@(@{ type='text'; text=@{ content=$t } }) } } }
function New-H3($t)  { @{ object='block'; type='heading_3'; heading_3=@{ rich_text=@(@{ type='text'; text=@{ content=$t } }) } } }
function New-Num($t) { @{ object='block'; type='numbered_list_item'; numbered_list_item=@{ rich_text=@(@{ type='text'; text=@{ content=$t } }) } } }

$blocks = @()
$blocks += New-H2('本週工作摘要')
$blocks += New-H1('【26便利】')
$i = 0
foreach ($c in $cats[0..3]) {
    if ($p26[$c].Count -gt 0) {
        $blocks += New-H3("$($cn[$i])、$c")
        foreach ($item in $p26[$c]) { $blocks += New-Num($item) }
    }; $i++
}
$blocks += New-H1('【99便利】')
$i = 0
foreach ($c in $cats[0..1]) {
    if ($p99[$c].Count -gt 0) {
        $blocks += New-H3("$($cn[$i])、$c")
        foreach ($item in $p99[$c]) { $blocks += New-Num($item) }
    }; $i++
}

$blocks += New-H2('下週計畫')
$blocks += New-H1('【26便利】')
if ($next26.Count -gt 0) { foreach ($item in $next26) { $blocks += New-Num($item) } }
else { $blocks += New-Num('（無進行中任務）') }
$blocks += New-H1('【99便利】')
if ($next99.Count -gt 0) { foreach ($item in $next99) { $blocks += New-Num($item) } }
else { $blocks += New-Num('（無進行中任務）') }

$blocks += New-H2('本週風險／問題')
if ($risks.Count -gt 0) { foreach ($item in $risks) { $blocks += New-Num($item) } }
else { $blocks += New-Num('無風險事項') }

$body = @{
    parent     = @{ page_id = '332a5eb0b51a81fba825d0117923d180' }
    properties = @{ title = @{ title = @(@{ text = @{ content = $title } }) } }
    children   = $blocks
} | ConvertTo-Json -Depth 15

$tmpN  = Join-Path $PSScriptRoot '.tmp_notion.json'
$tmpNR = Join-Path $PSScriptRoot '.tmp_notion_r.json'
[System.IO.File]::WriteAllText($tmpN, $body, [System.Text.Encoding]::UTF8)
curl.exe -s -X POST 'https://api.notion.com/v1/pages' `
    -H "Authorization: Bearer $notionToken" -H 'Notion-Version: 2022-06-28' `
    -H 'Content-Type: application/json' -o $tmpNR --data-binary "@$tmpN"
Remove-Item $tmpN -ErrorAction SilentlyContinue
$nr = [System.IO.File]::ReadAllText($tmpNR, [System.Text.Encoding]::UTF8)
Remove-Item $tmpNR -ErrorAction SilentlyContinue

if ($nr -match '"url":"(https://www\.notion\.so/[^"]+)"') {
    Write-Host "Notion OK: $($matches[1])" -ForegroundColor Green
} else {
    Write-Host 'Notion FAILED:' -ForegroundColor Red
    Write-Host ($nr.Substring(0, [Math]::Min(300, $nr.Length)))
}
