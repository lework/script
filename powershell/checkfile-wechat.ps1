function wechattalk()
{
  curl -Method Get "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxxxxx"
}

$msg= "Windows Server备份失败通知！
"
$counter= 0

#备份检查
if (Get-ChildItem D:\serverbackup\WindowsImageBackup\test\Catalog | Where{$_.LastWriteTime -lt (Get-Date).AddDays(-32)})
{
    $msg= $msg +
    "
    ○ test（10.8.8.1）：
    "
    $counter= $counter + 1
}

if ($counter -eq 0){
    $msg= "Windows Server 备份检查完成，备份状态正常！"
}

$msg= $msg +
"
    告警来源 127.0.0.1
"

wechattalk