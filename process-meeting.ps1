# 會議記錄自動化 - PowerShell 版本
# 用途: 自動寫入會議記錄到 Notion，並提取原創待辦項目到 PM 任務追蹤

param(
    [Parameter(Mandatory=$true, HelpMessage="會議記錄內容或網址")]
    [string]$MeetingContent,

    [Parameter(Mandatory=$false, HelpMessage="Google Doc 連結")]
    [string]$GoogleDocUrl = ""
)

# 載入環境變數
$env:PSModulePath += ";$PSScriptRoot"
$envPath = Join-Path $PSScriptRoot ".env"
if (Test-Path $envPath) {
    $envContent = Get-Content $envPath
    foreach ($line in $envContent) {
        if ($line -match '^\s*([^=]+)=(.+)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
        }
    }
}

$NotionToken = $env:NOTION_TOKEN
if (-not $NotionToken) {
    Write-Host "❌ 錯誤: NOTION_TOKEN 未設定" -ForegroundColor Red
    exit 1
}

# Notion 資料庫配置
$MeetingIndexDbId = "d6631ef7-a725-413f-a1d2-cee72f2f1532"
$PMTasksDbId = "088c899f-2a18-4f72-b81b-1a960207fb54"

# ============================================
# 函數：解析會議記錄
# ============================================
function Parse-MeetingContent {
    param([string]$Content)

    $result = @{
        Date = ""
        MeetingName = ""
        Attendees = ""
        KeyDecision = ""
        ActionItemsText = ""
        MeetingParticipants = @()
        Project = "26便利"
        MeetingType = "例行週會"
        OriginalCreativeTasksCount = 0
        Content = $Content
    }

    $lines = $Content -split "`n"

    # 提取日期（第一行通常包含日期和會議名稱）
    if ($lines.Count -gt 0) {
        $firstLine = $lines[0]

        # 試著匹配日期格式
        if ($firstLine -match "(\d{4})年(\d{1,2})月(\d{1,2})日") {
            $result.Date = "{0}-{1:D2}-{2:D2}" -f [int]$matches[1], [int]$matches[2], [int]$matches[3]
        } elseif ($firstLine -match "(\d{4})-(\d{1,2})-(\d{1,2})") {
            $result.Date = "{0}-{1:D2}-{2:D2}" -f [int]$matches[1], [int]$matches[2], [int]$matches[3]
        } elseif ($firstLine -match "(\d{4})/(\d{1,2})/(\d{1,2})") {
            $result.Date = "{0}-{1:D2}-{2:D2}" -f [int]$matches[1], [int]$matches[2], [int]$matches[3]
        } else {
            $result.Date = (Get-Date).ToString("yyyy-MM-dd")
        }

        # 提取會議名稱
        if ($firstLine -match "\|\s*(.+)$") {
            $result.MeetingName = $matches[1].Trim()
        } else {
            $result.MeetingName = $firstLine.Substring(0, [Math]::Min(50, $firstLine.Length)).Trim()
        }
    }

    # 提取參與者
    $attendeesMatch = $Content | Select-String "(?:參與者|與會者|出席者)[：:]?\s*(.+?)(?=`n|$)" | Select-Object -First 1
    if ($attendeesMatch) {
        $result.Attendees = $attendeesMatch.Matches.Groups[1].Value.Trim()
    }

    # 提取待辦事項部分
    $actionItemsMatch = $Content | Select-String "(?:待辦|待辦事項|行動項目)[：:\s]*(.+?)(?=`n`n|$)" -AllMatches
    if ($actionItemsMatch) {
        $result.ActionItemsText = $actionItemsMatch.Matches[0].Groups[1].Value
    }

    # 提取關鍵決議
    $decisionsMatch = $Content | Select-String "(?:決議|決定|結論|會議總結)[：:]?\s*(.+?)(?=`n|$)" | Select-Object -First 1
    if ($decisionsMatch) {
        $decision = $decisionsMatch.Matches.Groups[1].Value
        $result.KeyDecision = $decision.Substring(0, [Math]::Min(150, $decision.Length))
    }

    # 判斷會議對象
    $result.MeetingParticipants = Infer-MeetingParticipants -Text ($result.Attendees + " " + $Content)

    # 判斷專案
    $result.Project = Infer-Project -Text $Content

    # 判斷會議類型
    $result.MeetingType = Infer-MeetingType -Text ($result.MeetingName + " " + $Content)

    # 統計原創待辦項目
    $result.OriginalCreativeTasksCount = Count-OriginalCreativeTasks -ActionItemsText $result.ActionItemsText

    return $result
}

# ============================================
# 函數：推斷會議對象
# ============================================
function Infer-MeetingParticipants {
    param([string]$Text)

    $participants = @()
    $mapping = @{
        "三叉" = "三叉"
        "唯晶" = "唯晶"
        "怪獸" = "怪獸"
        "Kent" = "Kent"
        "Emily" = "Emily"
        "Albert" = "Albert"
        "銀河" = "銀河"
        "法務" = "法務"
        "營運" = "營運"
        "原創" = "原創"
        "Lisa" = "原創"
        "Licca" = "原創"
        "Mark" = "原創"
    }

    foreach ($key in $mapping.Keys) {
        if ($Text.Contains($key) -and -not $participants.Contains($mapping[$key])) {
            $participants += $mapping[$key]
        }
    }

    if ($participants.Count -eq 0) {
        $participants = @("原創")
    }

    return $participants
}

# ============================================
# 函數：推斷專案
# ============================================
function Infer-Project {
    param([string]$Text)

    if ($Text.Contains("99便利") -or $Text.Contains("99")) {
        return "99便利"
    }
    return "26便利"
}

# ============================================
# 函數：推斷會議類型
# ============================================
function Infer-MeetingType {
    param([string]$Text)

    $typeMap = @{
        "例行" = "例行週會"
        "週會" = "例行週會"
        "對齊" = "功能對齊"
        "美術" = "美術審查"
        "審查" = "美術審查"
        "驗收" = "版本驗收"
        "緊急" = "緊急協調"
        "月進度" = "月進度會"
        "月報" = "月進度會"
    }

    foreach ($key in $typeMap.Keys) {
        if ($Text.Contains($key)) {
            return $typeMap[$key]
        }
    }

    return "例行週會"
}

# ============================================
# 函數：統計原創待辦項目
# ============================================
function Count-OriginalCreativeTasks {
    param([string]$ActionItemsText)

    $lines = $ActionItemsText -split "`n"
    $inOriginalSection = $false
    $count = 0

    foreach ($line in $lines) {
        if ($line.Contains("原創") -or $line.Contains("【原創】")) {
            $inOriginalSection = $true
        } elseif ($line -match "^【.*】" -and -not $line.Contains("原創")) {
            $inOriginalSection = $false
        }

        if ($inOriginalSection -and $line -match "^\d+\.|^[-*]") {
            $count++
        }
    }

    return $count
}

# ============================================
# 函數：提取原創待辦項目
# ============================================
function Extract-OriginalCreativeTasks {
    param([string]$ActionItemsText)

    $tasks = @()
    $lines = $ActionItemsText -split "`n"
    $inOriginalSection = $false
    $currentTask = ""

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        if ($trimmed.Contains("原創") -or $trimmed.Contains("【原創】")) {
            $inOriginalSection = $true
            continue
        } elseif ($trimmed -match "^【.*】" -and -not $trimmed.Contains("原創")) {
            $inOriginalSection = $false
            if ($currentTask) {
                $tasks += $currentTask
                $currentTask = ""
            }
            continue
        }

        if ($inOriginalSection -and $trimmed) {
            if ($trimmed -match "^\d+\.\s*(.+)$|^[-*]\s*(.+)$") {
                if ($currentTask) {
                    $tasks += $currentTask
                }
                $currentTask = $matches[1] -or $matches[2]
            } elseif ($currentTask -and $trimmed) {
                $currentTask += " " + $trimmed
            }
        }
    }

    if ($currentTask) {
        $tasks += $currentTask
    }

    return $tasks
}

# ============================================
# 函數：呼叫 Notion API - 建立頁面
# ============================================
function Create-NotionPage {
    param(
        [string]$DatabaseId,
        [hashtable]$Properties,
        [array]$Children = @()
    )

    $headers = @{
        "Authorization" = "Bearer $NotionToken"
        "Notion-Version" = "2022-06-28"
        "Content-Type" = "application/json"
    }

    $body = @{
        parent = @{
            database_id = $DatabaseId
        }
        properties = $Properties
    }

    if ($Children.Count -gt 0) {
        $body["children"] = $Children
    }

    $bodyJson = $body | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-WebRequest -Uri "https://api.notion.com/v1/pages" `
            -Method Post `
            -Headers $headers `
            -Body $bodyJson `
            -ContentType "application/json"

        $result = $response.Content | ConvertFrom-Json
        return $result
    } catch {
        Write-Host "❌ API 呼叫失敗: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# ============================================
# 函數：建立會議記錄索引頁面
# ============================================
function Create-MeetingIndexPage {
    param([hashtable]$MeetingData)

    Write-Host "💾 寫入會議記錄索引..." -ForegroundColor Cyan

    $properties = @{
        "會議名稱" = @{
            title = @(
                @{
                    text = @{
                        content = $MeetingData.MeetingName
                    }
                }
            )
        }
        "日期" = @{
            date = @{
                start = $MeetingData.Date
            }
        }
        "專案" = @{
            select = @{
                name = $MeetingData.Project
            }
        }
        "會議對象" = @{
            multi_select = @($MeetingData.MeetingParticipants | ForEach-Object { @{ name = $_ } })
        }
        "會議類型" = @{
            select = @{
                name = $MeetingData.MeetingType
            }
        }
        "版本號" = @{
            select = @{
                name = "不限版本"
            }
        }
        "關鍵決議" = @{
            rich_text = @(
                @{
                    text = @{
                        content = $MeetingData.KeyDecision
                    }
                }
            )
        }
        "待辦數量" = @{
            number = $MeetingData.OriginalCreativeTasksCount
        }
        "需跟進" = @{
            checkbox = ($MeetingData.OriginalCreativeTasksCount -gt 0)
        }
    }

    if ($GoogleDocUrl) {
        $properties["Google Doc 連結"] = @{
            url = $GoogleDocUrl
        }
    }

    $children = @(
        @{
            object = "block"
            type = "heading_2"
            heading_2 = @{
                rich_text = @(
                    @{
                        text = @{
                            content = "會議總結"
                        }
                    }
                )
            }
        },
        @{
            object = "block"
            type = "paragraph"
            paragraph = @{
                rich_text = @(
                    @{
                        text = @{
                            content = $MeetingData.Content.Substring(0, [Math]::Min(200, $MeetingData.Content.Length))
                        }
                    }
                )
            }
        },
        @{
            object = "block"
            type = "heading_2"
            heading_2 = @{
                rich_text = @(
                    @{
                        text = @{
                            content = "待辦事項"
                        }
                    }
                )
            }
        }
    )

    try {
        $page = Create-NotionPage -DatabaseId $MeetingIndexDbId -Properties $properties -Children $children
        Write-Host "✅ 會議索引: $($page.url)" -ForegroundColor Green
        return $page
    } catch {
        Write-Host "❌ 建立會議索引失敗" -ForegroundColor Red
        throw
    }
}

# ============================================
# 函數：計算週次
# ============================================
function Get-WeekNumber {
    param([string]$DateStr)

    $date = [datetime]::ParseExact($DateStr, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $weekNumber = $culture.Calendar.GetWeekOfYear($date, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)

    return "{0}/{1:D2} W{2}" -f $date.Year, $date.Month, $weekNumber
}

# ============================================
# 函數：建立 PM 任務
# ============================================
function Create-PMTasks {
    param([hashtable]$MeetingData, [string]$TodayDate)

    $tasks = Extract-OriginalCreativeTasks -ActionItemsText $MeetingData.ActionItemsText
    $createdTasks = @()

    if ($tasks.Count -eq 0) {
        Write-Host "⚠️  無原創待辦項目" -ForegroundColor Yellow
        return $createdTasks
    }

    Write-Host "💾 寫入 PM 待辦任務..." -ForegroundColor Cyan

    foreach ($task in $tasks) {
        $taskName = $task.Substring(0, [Math]::Min(100, $task.Length))
        $weekNumber = Get-WeekNumber -DateStr $MeetingData.Date

        $properties = @{
            "任務名稱" = @{
                title = @(
                    @{
                        text = @{
                            content = $taskName
                        }
                    }
                )
            }
            "專案" = @{
                select = @{
                    name = $MeetingData.Project
                }
            }
            "狀態" = @{
                select = @{
                    name = "進行中"
                }
            }
            "類型" = @{
                select = @{
                    name = "跨部門協作"
                }
            }
            "負責對象" = @{
                rich_text = @(
                    @{
                        text = @{
                            content = "原創"
                        }
                    }
                )
            }
            "開始日期" = @{
                date = @{
                    start = $MeetingData.Date
                }
            }
            "更新日期" = @{
                date = @{
                    start = $TodayDate
                }
            }
            "週次" = @{
                rich_text = @(
                    @{
                        text = @{
                            content = $weekNumber
                        }
                    }
                )
            }
            "說明" = @{
                rich_text = @(
                    @{
                        text = @{
                            content = "來自 $($MeetingData.MeetingName)"
                        }
                    }
                )
            }
        }

        try {
            $page = Create-NotionPage -DatabaseId $PMTasksDbId -Properties $properties
            $createdTasks += @{
                Name = $taskName
                Url = $page.url
            }
            Write-Host "   ✅ $taskName" -ForegroundColor Green
        } catch {
            Write-Host "   ❌ 失敗: $taskName" -ForegroundColor Red
        }
    }

    return $createdTasks
}

# ============================================
# 主程式
# ============================================
function Main {
    Write-Host "🔍 解析會議記錄..." -ForegroundColor Cyan

    $meetingData = Parse-MeetingContent -Content $MeetingContent

    Write-Host ""
    Write-Host "📅 日期: $($meetingData.Date)" -ForegroundColor White
    Write-Host "📋 會議: $($meetingData.MeetingName)" -ForegroundColor White
    Write-Host "🏢 專案: $($meetingData.Project)" -ForegroundColor White
    Write-Host "👥 參與者: $($meetingData.MeetingParticipants -join ', ')" -ForegroundColor White
    Write-Host "📝 待辦: $($meetingData.OriginalCreativeTasksCount) 項" -ForegroundColor White
    Write-Host ""

    # 建立會議索引頁面
    try {
        $meetingPage = Create-MeetingIndexPage -MeetingData $meetingData
        Write-Host ""
    } catch {
        Write-Host "❌ 無法建立會議記錄" -ForegroundColor Red
        exit 1
    }

    # 建立 PM 任務
    if ($meetingData.OriginalCreativeTasksCount -gt 0) {
        $todayDate = (Get-Date).ToString("yyyy-MM-dd")
        $createdTasks = Create-PMTasks -MeetingData $meetingData -TodayDate $todayDate

        Write-Host ""
        Write-Host "✅ 新增 $($createdTasks.Count) 項任務："
        foreach ($task in $createdTasks) {
            Write-Host "   📌 $($task.Name)" -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-Host "✨ 自動化完成！" -ForegroundColor Green
}

Main
