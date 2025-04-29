# 设置错误处理
$ErrorActionPreference = "Stop"

# 设置TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 日志函数
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Output $logMessage
}

# 通知
function Send-WeChatMessage {
  param (
    [string]$Message,
    [string]$Level = "warning"
  )

  $webhookUrl = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"
  $ipAddress = (Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'True'").IPAddress[0]

  $payload =  @{
        "msgtype" = "markdown"
        "markdown" = @{
            "content" = "[URL Status] $ipAddress `n> 发送时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') `n> <font color=""$level"">$message</font>"
        }
    }
  try {
    Invoke-RestMethod -Uri $webhookUrl -Method Post -Body ($payload | ConvertTo-Json)  -ContentType 'application/json;charset=utf-8'
  } catch {
    Write-Log "发送消息失败: $_" "ERROR"
  }
}

try {
    Write-Log "开始检查URL状态..."
    
    # 发送HTTP请求获取状态
    $apiUrl = "http://127.0.0.1/api/v1/status"
    Write-Log "正在请求API: $apiUrl"
    
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
    
    # 检查所有状态字段
    $wsUpstreamStatus = $response.data.ws.upstream.status
    $wsAuthStatus = $response.data.ws.auth.status
    $adStatus = $response.data.ad.status
    
    Write-Log "WS Upstream状态: $wsUpstreamStatus"
    Write-Log "WS Auth状态: $wsAuthStatus"
    Write-Log "AD状态: $adStatus"
    
    # 检查是否所有状态都是"连接完成"
    $allConnected = ($wsUpstreamStatus -eq "连接完成2") -and 
                    ($wsAuthStatus -eq "连接完成") -and 
                    ($adStatus -eq "连接完成")
    
    if (-not $allConnected) {
        Write-Log "检测到连接异常，准备重启AuthingADConnector服务..." "WARNING"
        Send-WeChatMessage "检测到连接异常，准备重启AuthingADConnector服务... `n> WS Upstream状态: $wsUpstreamStatus `n> WS Auth状态: $wsAuthStatus `n> AD状态: $adStatus" "warning"
        # 获取服务状态
        $service = Get-Service -Name "AuthingADConnector" -ErrorAction SilentlyContinue
        
        if ($service -ne $null) {
            Write-Log "重启AuthingADConnector服务..." "WARNING"
            Restart-Service -Name "AuthingADConnector" -Force
            Write-Log "AuthingADConnector服务已重启" "WARNING"
            
            # 等待服务启动
            Start-Sleep -Seconds 5
            $service = Get-Service -Name "AuthingADConnector"
            Write-Log "服务当前状态: $($service.Status)" "WARNING"
            if ($service.Status -eq "Running") {
                Send-WeChatMessage "AuthingADConnector 服务已重启" "info"
            } else {
                Send-WeChatMessage "AuthingADConnector 服务重启失败" "warning"
            }
        } else {
            Send-WeChatMessage "未找到AuthingADConnector服务" "warning"
            Write-Log "未找到AuthingADConnector服务" "ERROR"
        }
    } else {
        Write-Log "所有连接状态正常，无需操作"
    }
}
catch {
    Write-Log "执行过程中出现错误: $_" "ERROR"
    Send-WeChatMessage "执行过程中出现错误: $_" "warning"
}
finally {
    Write-Log "检查完成"
}

# 以下是创建计划任务的命令，需要时可以取消注释并执行
<#
# 创建计划任务，每5分钟执行一次
$taskName = "Check_URL_Status"
$scriptPath = "c:\scripts\check_url_status.ps1"

# 删除可能已存在的同名任务
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# 使用SchTasks.exe创建计划任务
$command = "SchTasks.exe /Create /SC MINUTE /MO 5 /TN $taskName /TR " + 
           "`"PowerShell.exe -ExecutionPolicy Bypass -NoProfile -File '$scriptPath'`"" + 
           " /RU SYSTEM /F"

# 执行命令创建任务
Invoke-Expression $command

Write-Output "已创建计划任务：$taskName，每5分钟执行一次"
#>
