
# 获取当前脚本的执行路径
$scriptPath = (Get-Location).Path

# 设置日志文件的路径
$logFile = Join-Path -Path $scriptPath -ChildPath "log.txt"

# 开始记录
Start-Transcript -Path $logFile -Append

# 您的代码或命令...
Write-Output "$(Get-Date): 开始执行脚本"


$vcenter_host= "xxxx"
$vcenter_user= "xxxx"
$vcenter_password= "xxxx"

$vm_list = "vm1", "vm2"
$vm_snapshot_name = "init"

$webhookUrl = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxxx"
$ipAddress = (Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'True'").IPAddress[0]

function Send-WeChatMessage {
    param(
        [Parameter(Mandatory=$true)]
        [string] $level,

        [Parameter(Mandatory=$true)]
        [string] $messageContent
    )

    $message = @{
        "msgtype" = "markdown"
        "markdown" = @{
            "content" = "[服务器快照恢复] $ipAddress <font color=""$level"">$messageContent</font>"
        }
    }

    $messageJson = ConvertTo-Json -Compress -InputObject $message
    Invoke-RestMethod -Method Post -Uri $webhookUrl -Body $messageJson -ContentType 'application/json;charset=utf-8'
}

function Quit {
    param(
        [Parameter()]
        [int]$exitCode = 0  # 默认退出码为0，表示正常退出
    )

    Write-Output "$(Get-Date): 脚本执行完成"
    # 停止记录
    Stop-Transcript
    [Environment]::Exit($exitCode)
}


try { 
    if (-not (Get-Module -Name "VMware.PowerCLI")) {
        Write-Output "$(Get-Date): 导入VMware.PowerCLI"
        # 如果模块没有被加载，那么导入它
        import-module VMware.PowerCLI -ErrorAction Stop
    }
}

catch {
    Write-Output "$(Get-Date): import-module VMware.PowerCLI, err: " + $_.Exception.Message.ToString()
    Send-WeChatMessage -level "warning" -messageContent "import-module VMware.PowerCLI Error"
    Quit -exitCode 1
}

Write-Output "$(Get-Date): 连接Vcenter"
try {
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
    Connect-VIServer -Server $vcenter_host -User $vcenter_user -Password $vcenter_password

    if (-not $?) {
        Send-WeChatMessage -level "warning" -messageContent "Connect-VIServer Error"
        Quit -exitCode 1
    }
}
catch {
    Write-Output "$(Get-Date): Connect-VIServer, err: $($_.Exception.Message)"
    Send-WeChatMessage -level "warning" -messageContent "Connect-VIServer Error"
    Quit -exitCode 1
}

Write-Output "$(Get-Date): 开始恢复快照"
foreach ($item in $vm_list) {
    Write-Output "$(Get-Date): $item to $vm_snapshot_name"
    try {
        $vm = Get-VM -Name $item
        $snapshot = Get-Snapshot -VM $vm -Name $vm_snapshot_name
        Set-VM -VM $vm -Snapshot $snapshot -Confirm:$false
    }
    catch {
        Write-Output "$(Get-Date): $_ to $vm_snapshot_name, err: $($_.Exception.Message)"
        Send-WeChatMessage -level "warning" -messageContent "$_ to $vm_snapshot_name Error"
    }
}

Write-Output "$(Get-Date): 恢复快照完成"
Disconnect-VIServer -Server $vcenter_host -Confirm:$false

#Send-WeChatMessage -level "info" -messageContent "恢复快照成功！"

Quit