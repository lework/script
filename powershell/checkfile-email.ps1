function sendmail()
{
    function mailoptions($mailaddr,$body) #定义发送邮件的方法
    {  
        $msg=New-Object System.Net.Mail.MailMessage  
        $msg.To.Add($mailaddr)  
        $msg.From = New-Object System.Net.Mail.MailAddress("notice@test.com", "备份点检员",[system.Text.Encoding]::GetEncoding("UTF-8"))   #发件人
        $msg.Subject = "Windows备份失败通知！"  
        $msg.SubjectEncoding = [system.Text.Encoding]::GetEncoding("UTF-8")  
        $msg.Body =$body    
        $msg.BodyEncoding = [system.Text.Encoding]::GetEncoding("UTF-8")  
        $msg.IsBodyHtml = $false #发送html格式邮件
        $client = New-Object System.Net.Mail.SmtpClient("smtp.qiye.163.com")  #配置smtp服务器
        $client.Port = 25 #指定smtp端口
        $client.UseDefaultCredentials = $false  
        $client.Credentials=New-Object System.Net.NetworkCredential("notice@test.com", "xxxxxxxx")  
        try {$client.Send($msg)}  
            catch [Exception]
            {$($_.Exception.Message)  
            $mailaddr  
            }
    }

    $tomailaddr = "ops@test.com"
    mailoptions $tomailaddr $Emailbody
}



$Emailbody= "Dear All :
"

$counter= 0

#test备份检查
if (Get-ChildItem D:\serverbackup\WindowsImageBackup\test\Catalog | Where{$_.LastWriteTime -lt (Get-Date).AddDays(-32)})
{
    $Emailbody= $Emailbody +
    "
    ○ test（10.8.8.1）：
    "
    $counter= $counter + 1
}

$Emailbody= $Emailbody +
"
    告警来源 127.0.0.1
"

if ($counter -gt 0)
{
    sendmail
}
