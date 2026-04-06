# 自動產出日報並寄送到 Gmail
# 用法：.\send-daily-report.ps1

$envFile = Join-Path $PSScriptRoot '.env'
$cfg = @{}
Get-Content $envFile -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { $cfg[$matches[1].Trim()] = $matches[2].Trim() }
}
$notionToken = $cfg['NOTION_TOKEN']
$gmail = $cfg['GMAIL_ADDRESS']
$gmailPass = $cfg['GMAIL_APP_PASSWORD']

Write-Host '讀取 Notion 任務中...'

# 篩選條件：
# 1. 狀態 ≠ 已完成 (進行中、待確認、追蹤中、阻礙)
# OR
# 2. 狀態 = 已完成 AND 更新日期在前 2 天內
$twoDaysAgo = (Get-Date).AddDays(-2).ToString('yyyy-MM-dd')
$today = (Get-Date).ToString('yyyy-MM-dd')

$filterBody = @"
{
  "filter": {
    "or": [
      {
        "property": "狀態",
        "select": { "does_not_equal": "已完成" }
      },
      {
        "and": [
          {
            "property": "狀態",
            "select": { "equals": "已完成" }
          },
          {
            "property": "上次編輯時間",
            "date": {
              "on_or_after": "$twoDaysAgo"
            }
          }
        ]
      }
    ]
  },
  "page_size": 50
}
"@

$tmpFilter = Join-Path $PSScriptRoot '.tmp_filter.json'
[System.IO.File]::WriteAllText($tmpFilter, $filterBody, [System.Text.Encoding]::UTF8)

$tmpResponse = Join-Path $PSScriptRoot '.tmp_response.json'
curl.exe -s -X POST 'https://api.notion.com/v1/databases/dd5ad18a-33d0-4190-ae85-f365d6024fb5/query' `
    -H "Authorization: Bearer $notionToken" `
    -H 'Notion-Version: 2022-06-28' `
    -H 'Content-Type: application/json' `
    --data-binary "@$tmpFilter" `
    -o $tmpResponse

Remove-Item $tmpFilter -ErrorAction SilentlyContinue

$data = [System.IO.File]::ReadAllText($tmpResponse, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
Remove-Item $tmpResponse -ErrorAction SilentlyContinue
$tasks = $data.results
Write-Host "取得 $($tasks.Count) 筆任務"

$statusOrder = @('進行中', '追蹤中', '待確認', '阻礙', '已完成')
$p26 = @{}; $p99 = @{}; $pOther = @{}
foreach ($s in $statusOrder) {
    $p26[$s] = @()
    $p99[$s] = @()
    $pOther[$s] = @()
}

# 去重集合
$seenLines = @{}

foreach ($t in $tasks) {
    $name   = $t.properties.'任務名稱'.title[0].plain_text
    $proj   = $t.properties.'專案'.select.name
    $status = $t.properties.'狀態'.select.name
    $note   = if ($t.properties.'備註/阻礙說明'.rich_text) { $t.properties.'備註/阻礙說明'.rich_text[0].plain_text } else { '' }
    $responsible = if ($t.properties.'負責對象'.multi_select) { $t.properties.'負責對象'.multi_select.name } else { @() }

    # 進度摘要來自備註欄
    $summary = if ($note) { $note } else { $status }
    if ($summary.Length -gt 60) { $summary = $summary.Substring(0, 60) + '...' }
    $line = "$name：$summary"

    # 檢查是否已經出現過此行（防止重複）
    if ($seenLines[$line]) { continue }
    $seenLines[$line] = $true

    # 判斷是否需要標紅（負責對象含老闆或Marlos）
    $isRed = ($responsible -contains '老闆') -or ($responsible -contains 'Marlos')

    # 建立任務物件，包含行文本和是否標紅
    $item = @{ Line = $line; IsRed = $isRed }

    # 按專案和狀態分組
    if ($proj -eq '26便利') { $p26[$status] += $item }
    elseif ($proj -eq '99便利') { $p99[$status] += $item }
    else { $pOther[$status] += $item }

    # Debug: 輸出第一個任務的信息
    if ($name -eq '商標申請推進（法務）') {
        Write-Host "DEBUG: Task '$name'" -ForegroundColor Cyan
        Write-Host "  Line: '$line'" -ForegroundColor Cyan
        Write-Host "  Item['Line']: '$($item['Line'])'" -ForegroundColor Cyan
    }
}

# ── 排程提醒輔助（26便利固定節奏） ───────────────────────────────────────────
$SCHED_HOLIDAYS = @(
    '2026-01-01',
    '2026-01-27','2026-01-28','2026-01-29','2026-01-30','2026-01-31','2026-02-02',
    '2026-02-28',
    '2026-04-03','2026-04-04','2026-04-05',
    '2026-05-01',
    '2026-06-19',
    '2026-09-25','2026-09-26','2026-09-27',
    '2026-10-09','2026-10-10'
)
function Test-SchedHoliday([datetime]$d) {
    $dow = [int]$d.DayOfWeek
    return ($dow -eq 0 -or $dow -eq 6) -or ($SCHED_HOLIDAYS -contains $d.ToString('yyyy-MM-dd'))
}
function Get-SchedWorkDay([datetime]$d) { while (Test-SchedHoliday $d) { $d=$d.AddDays(1) }; return $d }
function Add-SchedMonth([int]$y,[int]$m,[int]$n) { $r=$m+$n; $ry=$y; while($r -gt 12){$r-=12;$ry++}; return @($ry,$r) }
function Safe-SchedDate([int]$y,[int]$m,[int]$d) { return [datetime]::new($y,$m,[Math]::Min($d,[datetime]::DaysInMonth($y,$m))) }

# 從 Notion 資料庫讀取版本映射
Write-Host '讀取版本里程碑資料...'
$versionDbFilter = '{"page_size":20}'
$tmpVersionFilter = Join-Path $PSScriptRoot '.tmp_version_filter.json'
$tmpVersionResponse = Join-Path $PSScriptRoot '.tmp_version_response.json'
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
$SCHED_VMAP = [ordered]@{}
$SCHED_VNOTES = @{}

foreach ($versionPage in $versionData.results) {
    $ver = $versionPage.properties.'版號'.title[0].plain_text
    $yearMonth = $versionPage.properties.'研發月份'.date.start
    $purpose = $versionPage.properties.'版本用途'.rich_text[0].plain_text

    if ($yearMonth) {
        $vDate = [datetime]::ParseExact($yearMonth, 'yyyy-MM-dd', $null)
        $SCHED_VMAP[$ver] = @($vDate.Year, $vDate.Month)

        # 提取特殊注意事項（如果包含老闆、AI NPC 等關鍵詞，或為測試版本）
        if ($purpose -match '老闆|AI|NPC|預計上線|CB|OB') {
            $note = $purpose
            if ($note.Length -gt 40) { $note = $note.Substring(0, 40) + '...' }
            $SCHED_VNOTES[$ver] = "⚠️ $note"
        }
    }
}

Write-Host "載入 $($SCHED_VMAP.Count) 個版本"

function Get-ScheduleLines([datetime]$d) {
    $out = @()
    $milestonesByDay = @{}
    $phasesByDay = @{}

    # 預先收集所有日期相關的里程碑和階段
    foreach ($kv in $SCHED_VMAP.GetEnumerator()) {
        $ver=$kv.Key; $ym=$kv.Value; $mY=$ym[0]; $mM=$ym[1]
        $m1=Add-SchedMonth $mY $mM 1; $m1Y=$m1[0]; $m1M=$m1[1]
        $m2=Add-SchedMonth $mY $mM 2; $m2Y=$m2[0]; $m2M=$m2[1]
        $phases = @(
            [PSCustomObject]@{Name='功能開發（不合併）';CalStart=Safe-SchedDate $mY $mM 1; CalEnd=Safe-SchedDate $mY $mM 8; WdStart=Get-SchedWorkDay(Safe-SchedDate $mY $mM 1); WdEnd=Get-SchedWorkDay(Safe-SchedDate $mY $mM 8)}
            [PSCustomObject]@{Name='三叉合併至 CSP';CalStart=Safe-SchedDate $mY $mM 9; CalEnd=Safe-SchedDate $mY $mM 16; WdStart=Get-SchedWorkDay(Safe-SchedDate $mY $mM 9); WdEnd=Get-SchedWorkDay(Safe-SchedDate $mY $mM 16)}
            [PSCustomObject]@{Name='唯晶合併至 CSP';CalStart=Safe-SchedDate $mY $mM 17; CalEnd=Safe-SchedDate $mY $mM 24; WdStart=Get-SchedWorkDay(Safe-SchedDate $mY $mM 17); WdEnd=Get-SchedWorkDay(Safe-SchedDate $mY $mM 24)}
            [PSCustomObject]@{Name='三叉包版';CalStart=Safe-SchedDate $mY $mM 25; CalEnd=Safe-SchedDate $mY $mM 30; WdStart=Get-SchedWorkDay(Safe-SchedDate $mY $mM 25); WdEnd=Get-SchedWorkDay(Safe-SchedDate $mY $mM 30)}
        )
        $milestones = @(
            [PSCustomObject]@{Date=Get-SchedWorkDay(Safe-SchedDate $mY $mM 26);  Label='PM 提供驗測清單給 QA';        Who='PM → 異起 QA'}
            [PSCustomObject]@{Date=Get-SchedWorkDay(Safe-SchedDate $m1Y $m1M 6); Label='三叉提供 TEST APK/IPA 給 QA'; Who='三叉開發 → 異起 QA'}
            [PSCustomObject]@{Date=Get-SchedWorkDay(Safe-SchedDate $m1Y $m1M 9); Label='驗測文件修正版';               Who='異起 QA'}
            [PSCustomObject]@{Date=Get-SchedWorkDay(Safe-SchedDate $m2Y $m2M 6); Label='三叉提供營運版本';              Who='三叉開發 → 營運'}
        )
        $activePhase = $phases | Where-Object { $d -ge $_.CalStart -and $d -le $_.CalEnd }
        $todayMs     = $milestones | Where-Object { $_.Date.Date -eq $d.Date }

        if ($todayMs.Count -gt 0) {
            if (-not $milestonesByDay[$d.Date]) { $milestonesByDay[$d.Date] = @() }
            foreach ($ms in $todayMs) {
                $note = if ($SCHED_VNOTES[$ver]) { "（$($SCHED_VNOTES[$ver])）" } else { '' }
                $milestonesByDay[$d.Date] += [PSCustomObject]@{Ver=$ver; Label=$ms.Label; Who=$ms.Who; Note=$note}
            }
        }

        if ($activePhase) {
            if (-not $phasesByDay[$d.Date]) { $phasesByDay[$d.Date] = @() }
            $note = if ($SCHED_VNOTES[$ver]) { "（$($SCHED_VNOTES[$ver])）" } else { '' }
            $isStart = ($d.Date -eq $activePhase.WdStart.Date)
            $isEnd   = ($d.Date -eq $activePhase.WdEnd.Date)
            $rem     = [int]($activePhase.WdEnd - $d).TotalDays
            $endStr  = $activePhase.WdEnd.ToString('MM/dd')
            if ($isEnd) {
                $phaseDesc = "$($activePhase.Name) 今日截止"
            } elseif ($isStart) {
                $phaseDesc = "$($activePhase.Name) 開始，截止 ${endStr}（共 ${rem} 天）"
            } else {
                $phaseDesc = "$($activePhase.Name) 進行中，截止 ${endStr}（剩餘 ${rem} 天）"
            }
            $phasesByDay[$d.Date] += [PSCustomObject]@{Ver=$ver; Desc=$phaseDesc; Note=$note}
        }
    }

    # 蒐集所有版本的所有相關里程碑（接下來 1-2 天內）
    $allMilestones = @()
    foreach ($kv in $SCHED_VMAP.GetEnumerator()) {
        $ver=$kv.Key; $ym=$kv.Value; $mY=$ym[0]; $mM=$ym[1]
        $m1=Add-SchedMonth $mY $mM 1; $m1Y=$m1[0]; $m1M=$m1[1]
        $m2=Add-SchedMonth $mY $mM 2; $m2Y=$m2[0]; $m2M=$m2[1]

        $milestones = @(
            [PSCustomObject]@{Date=Get-SchedWorkDay(Safe-SchedDate $mY $mM 26);  Label='PM 提供驗測清單給 QA'}
            [PSCustomObject]@{Date=Get-SchedWorkDay(Safe-SchedDate $m1Y $m1M 6); Label='三叉提供 TEST APK/IPA 給 QA'}
            [PSCustomObject]@{Date=Get-SchedWorkDay(Safe-SchedDate $m1Y $m1M 9); Label='驗測文件修正版'}
            [PSCustomObject]@{Date=Get-SchedWorkDay(Safe-SchedDate $m2Y $m2M 6); Label='三叉提供營運版本'}
        )

        foreach ($ms in $milestones) {
            $daysUntil = [int]($ms.Date - $d).TotalDays
            # 顯示接下來 1-2 天內的里程碑（不限正好當日）
            if ($daysUntil -ge 0 -and $daysUntil -le 2) {
                $note = if ($SCHED_VNOTES[$ver]) { "（$($SCHED_VNOTES[$ver])）" } else { '' }
                $dateStr = $ms.Date.ToString('MM/dd')
                if ($daysUntil -eq 0) {
                    $timeStr = '（今日）'
                } else {
                    $timeStr = "（剩餘 $daysUntil 天）"
                }
                $allMilestones += [PSCustomObject]@{Ver=$ver; Label=$ms.Label; DateStr=$dateStr; TimeStr=$timeStr; Note=$note}
            }
        }
    }

    # 輸出所有里程碑（按版本排序）
    foreach ($ms in $allMilestones | Sort-Object Ver) {
        $out += "26便利 v$($ms.Ver)：$($ms.Label)，截止 $($ms.DateStr)$($ms.TimeStr)$($ms.Note)"
    }

    # 輸出所有階段（同日期多版本都列出）
    if ($phasesByDay[$d.Date]) {
        foreach ($ph in $phasesByDay[$d.Date]) {
            $out += "26便利 v$($ph.Ver)：$($ph.Desc)$($ph.Note)"
        }
    }

    return $out
}
# ─────────────────────────────────────────────────────────────────────────────

$reportDate = (Get-Date).AddDays(1).Date
$today = $reportDate.ToString('yyyy/MM/dd')

# 純文字版本（終端輸出）
$lines = @()
$lines += "$today 早會報告"
$lines += ''
$lines += '【26便利】'
foreach ($s in $statusOrder) {
    if ($p26[$s].Count -gt 0) {
        $lines += $s
        $n = 1; foreach ($item in $p26[$s]) { $lines += "$n. $($item.Line)"; $n++ }
        $lines += ''
    }
}
$lines += ''
$lines += '【99便利】'
foreach ($s in $statusOrder) {
    if ($p99[$s].Count -gt 0) {
        $lines += $s
        $n = 1; foreach ($item in $p99[$s]) { $lines += "$n. $($item.Line)"; $n++ }
        $lines += ''
    }
}
if ($pOther | Measure-Object | Select-Object -ExpandProperty Count) {
    $hasOther = $false
    foreach ($s in $statusOrder) {
        if ($pOther[$s].Count -gt 0) { $hasOther = $true; break }
    }
    if ($hasOther) {
        $lines += ''
        $lines += '【其他】'
        foreach ($s in $statusOrder) {
            if ($pOther[$s].Count -gt 0) {
                $lines += $s
                $n = 1; foreach ($item in $pOther[$s]) { $lines += "$n. $($item.Line)"; $n++ }
                $lines += ''
            }
        }
    }
}

# 附加排程提醒（若明日有節點）
$schedLines = Get-ScheduleLines $reportDate
if ($schedLines.Count -gt 0) {
    $lines += ''
    $lines += '【排程提醒】'
    foreach ($sl in $schedLines) { $lines += "* $sl" }
}

$report = $lines -join "`n"
Write-Host $report

# HTML 版本（Email 用）
$htmlLines = @()
$htmlLines += "<b>$today 早會報告</b><br>"
$htmlLines += '<br>'
$htmlLines += "<b>【26便利】</b><br>"
foreach ($s in $statusOrder) {
    if ($p26[$s].Count -gt 0) {
        $htmlLines += "<b>$s</b><br>"
        $n = 1; foreach ($item in $p26[$s]) {
            if ($item.IsRed) {
                $htmlLines += "$n. <span style=`"color:red;font-weight:bold`">$($item.Line)</span><br>"
            } else {
                $htmlLines += "$n. $($item.Line)<br>"
            }
            $n++
        }
        $htmlLines += "<br>"
    }
}

$htmlLines += "<b>【99便利】</b><br>"
foreach ($s in $statusOrder) {
    if ($p99[$s].Count -gt 0) {
        $htmlLines += "<b>$s</b><br>"
        $n = 1; foreach ($item in $p99[$s]) {
            if ($item.IsRed) {
                $htmlLines += "$n. <span style=`"color:red;font-weight:bold`">$($item.Line)</span><br>"
            } else {
                $htmlLines += "$n. $($item.Line)<br>"
            }
            $n++
        }
        $htmlLines += "<br>"
    }
}

if ($pOther | Measure-Object | Select-Object -ExpandProperty Count) {
    $hasOther = $false
    foreach ($s in $statusOrder) {
        if ($pOther[$s].Count -gt 0) { $hasOther = $true; break }
    }
    if ($hasOther) {
        $htmlLines += "<b>【其他】</b><br>"
        foreach ($s in $statusOrder) {
            if ($pOther[$s].Count -gt 0) {
                $htmlLines += "<b>$s</b><br>"
                $n = 1; foreach ($item in $pOther[$s]) {
                    if ($item.IsRed) {
                        $htmlLines += "$n. <span style=`"color:red;font-weight:bold`">$($item.Line)</span><br>"
                    } else {
                        $htmlLines += "$n. $($item.Line)<br>"
                    }
                    $n++
                }
                $htmlLines += "<br>"
            }
        }
    }
}

if ($schedLines.Count -gt 0) {
    $htmlLines += "<b>【排程提醒】</b><br>"
    foreach ($sl in $schedLines) { $htmlLines += "* $sl<br>" }
}

$reportHtml = $htmlLines -join ""

Write-Host '寄送 Email 中...'
$subject = "$today 早會日報"

Send-MailMessage `
    -From $gmail `
    -To $gmail `
    -Subject $subject `
    -Body $reportHtml `
    -BodyAsHtml `
    -Encoding UTF8 `
    -SmtpServer 'smtp.gmail.com' `
    -Port 587 `
    -UseSsl `
    -Credential (New-Object System.Management.Automation.PSCredential($gmail, (ConvertTo-SecureString $gmailPass -AsPlainText -Force)))

Write-Host '日報已寄出！' -ForegroundColor Green

# 寫入 Notion wiki
Write-Host 'Writing to Notion...'

function New-H1($t) {
    $h = [ordered]@{}
    $h['object'] = 'block'
    $h['type'] = 'heading_1'
    $h['heading_1'] = @{
        'rich_text' = @( @{
            'type' = 'text'
            'text' = @{ 'content' = [string]$t }
        } )
    }
    $h
}

function New-H2($t) {
    $h = [ordered]@{}
    $h['object'] = 'block'
    $h['type'] = 'heading_2'
    $h['heading_2'] = @{
        'rich_text' = @( @{
            'type' = 'text'
            'text' = @{ 'content' = [string]$t }
        } )
    }
    $h
}

function New-Num([string]$content, [bool]$isRed = $false) {
    $h = [ordered]@{}
    $h['object'] = 'block'
    $h['type'] = 'numbered_list_item'

    $richItem = @{}
    $richItem['type'] = 'text'
    $richItem['text'] = @{ 'content' = $content }

    if ($isRed) {
        $richItem['annotations'] = @{
            'bold' = $false
            'italic' = $false
            'strikethrough' = $false
            'underline' = $false
            'code' = $false
            'color' = 'red'
        }
    }

    $h['numbered_list_item'] = @{
        'rich_text' = @( $richItem )
    }
    $h
}

$blocks = @()
$blocks += New-H1('【26便利】')
foreach ($s in $statusOrder) {
    if ($p26[$s].Count -gt 0) {
        $blocks += New-H2($s)
        foreach ($item in $p26[$s]) {
            # Debug: 只在進行中分類的第一項時輸出
            if ($s -eq '進行中' -and ($blocks.Count -eq 2)) {
                Write-Host "DEBUG Blocks Build:" -ForegroundColor Magenta
                Write-Host "  item type: $($item.GetType().Name)" -ForegroundColor Magenta
                Write-Host "  item value: $item" -ForegroundColor Magenta
                if ($item -is [hashtable]) {
                    Write-Host "  item['Line']: $($item['Line'])" -ForegroundColor Magenta
                    Write-Host "  item.Line: $($item.Line)" -ForegroundColor Magenta
                }
            }

            $cleanLine = [string]($item['Line'])
            $isRed = [bool]($item['IsRed'])

            # Debug: 輸出轉換後的 cleanLine (只在第一項)
            if ($s -eq '進行中' -and ($blocks.Count -eq 2)) {
                Write-Host "  cleanLine: '$cleanLine'" -ForegroundColor Magenta
                Write-Host "  isRed: $isRed (type: $($isRed.GetType().Name))" -ForegroundColor Magenta
            }

            $blocks += New-Num($cleanLine, $isRed)
        }
    }
}
$blocks += New-H1('【99便利】')
foreach ($s in $statusOrder) {
    if ($p99[$s].Count -gt 0) {
        $blocks += New-H2($s)
        foreach ($item in $p99[$s]) {
            $cleanLine = [string]($item['Line'])
            $isRed = [bool]($item['IsRed'])
            $blocks += New-Num($cleanLine, $isRed)
        }
    }
}
if ($pOther | Measure-Object | Select-Object -ExpandProperty Count) {
    $hasOther = $false
    foreach ($s in $statusOrder) {
        if ($pOther[$s].Count -gt 0) { $hasOther = $true; break }
    }
    if ($hasOther) {
        $blocks += New-H1('【其他】')
        foreach ($s in $statusOrder) {
            if ($pOther[$s].Count -gt 0) {
                $blocks += New-H2($s)
                foreach ($item in $pOther[$s]) {
                    $cleanLine = [string]($item['Line'])
                    $isRed = [bool]($item['IsRed'])
                    $blocks += New-Num($cleanLine, $isRed)
                }
            }
        }
    }
}

# Notion 排程提醒區塊
if ($schedLines.Count -gt 0) {
    $blocks += New-H1('【排程提醒】')
    foreach ($sl in $schedLines) { $blocks += New-Num($sl, $false) }
}

# 改用 Notion blocks 而不是 markdown，直接產生正確的格式
$blocks = @()

# 【26便利】
$blocks += @{ object = 'block'; type = 'heading_1'; heading_1 = @{ rich_text = @(@{ type = 'text'; text = @{ content = '【26便利】' } }) } }
foreach ($s in $statusOrder) {
    if ($p26[$s].Count -gt 0) {
        $blocks += @{ object = 'block'; type = 'heading_2'; heading_2 = @{ rich_text = @(@{ type = 'text'; text = @{ content = $s } }) } }
        $itemList = @()
        $n = 1
        foreach ($item in $p26[$s]) {
            $lineText = "$n. "
            if ($item.IsRed) {
                $lineText += "🔴 "
            }
            $lineText += $item.Line
            $itemList += $lineText
            $n++
        }
        foreach ($line in $itemList) {
            $blocks += @{ object = 'block'; type = 'paragraph'; paragraph = @{ rich_text = @(@{ type = 'text'; text = @{ content = $line } }) } }
        }
    }
}

# 【99便利】
$blocks += @{ object = 'block'; type = 'heading_1'; heading_1 = @{ rich_text = @(@{ type = 'text'; text = @{ content = '【99便利】' } }) } }
foreach ($s in $statusOrder) {
    if ($p99[$s].Count -gt 0) {
        $blocks += @{ object = 'block'; type = 'heading_2'; heading_2 = @{ rich_text = @(@{ type = 'text'; text = @{ content = $s } }) } }
        $itemList = @()
        $n = 1
        foreach ($item in $p99[$s]) {
            $lineText = "$n. "
            if ($item.IsRed) {
                $lineText += "🔴 "
            }
            $lineText += $item.Line
            $itemList += $lineText
            $n++
        }
        foreach ($line in $itemList) {
            $blocks += @{ object = 'block'; type = 'paragraph'; paragraph = @{ rich_text = @(@{ type = 'text'; text = @{ content = $line } }) } }
        }
    }
}

# 【排程提醒】
if ($schedLines.Count -gt 0) {
    $blocks += @{ object = 'block'; type = 'heading_1'; heading_1 = @{ rich_text = @(@{ type = 'text'; text = @{ content = '【排程提醒】' } }) } }
    foreach ($sl in $schedLines) {
        $blocks += @{ object = 'block'; type = 'paragraph'; paragraph = @{ rich_text = @(@{ type = 'text'; text = @{ content = "* $sl" } }) } }
    }
}

$notionPage = @{
    parent = @{ page_id = '337a5eb0b51a8129835beb17168256be' }
    properties = @{
        title = @{ title = @(@{ text = @{ content = $today + ' 早會報告' } }) }
    }
    children = $blocks
} | ConvertTo-Json -Depth 15

$tmpNotion = Join-Path $PSScriptRoot '.tmp_notion.json'
[System.IO.File]::WriteAllText($tmpNotion, $notionPage, [System.Text.Encoding]::UTF8)

# Debug: 輸出原始任務物件和轉換後的 JSON
Write-Host "DEBUG: Raw blocks[2]:" -ForegroundColor Yellow
$blocks[2] | Format-List | Out-String | Write-Host

Write-Host "DEBUG: First task block content:" -ForegroundColor Yellow
$blocks[2] | ConvertTo-Json -Depth 10 | Write-Host

$notionResult = Join-Path $PSScriptRoot '.tmp_notion_result.json'
curl.exe -s -X POST 'https://api.notion.com/v1/pages' `
    -H "Authorization: Bearer $notionToken" `
    -H 'Notion-Version: 2022-06-28' `
    -H 'Content-Type: application/json' `
    -o $notionResult `
    --data-binary "@$tmpNotion"

Remove-Item $tmpNotion -ErrorAction SilentlyContinue
$nr = [System.IO.File]::ReadAllText($notionResult, [System.Text.Encoding]::UTF8)

if ($nr -match '"object":"error"') {
    Write-Host '【Notion API 錯誤】' -ForegroundColor Red
    Write-Host $nr
} elseif ($nr -match '"url":"(https://www\.notion\.so/[^"]+)"') {
    Write-Host "已寫入 Notion：$($matches[1])" -ForegroundColor Green
} else {
    Write-Host '寫入 Notion 失敗 - 無法解析回應' -ForegroundColor Red
    Write-Host $nr
}

Remove-Item $notionResult -ErrorAction SilentlyContinue