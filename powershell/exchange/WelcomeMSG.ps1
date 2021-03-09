#Disclaimer:
#The sample scripts are not supported under any Microsoft standard support program or service. The sample scripts are provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.


#Parameters to change:

# 1. Location of the HTML file:
$welcomemsg="C:\scripts\Microsoft-Welcome.html"
# 2. Email address of the welcome email sender (any email address in your domain):
$Sender="SYSTEM@msft.net"
# 3. Subject of the welcome email message:
$Sub="Welcome to MSFT"
# 4. hr represents the amount of time in hours the script checks for new mailboxes. 
#    The default is 1 hour back, means that it checks which mailboxes were created in the last hour.
$hr="1"

#End Parameters


$dom=$sender.Split("@") | Select-Object -Last 1
$StartDate = (Get-Date).AddHours(-$hr)
$srvsmtp=Get-PSSession | ? {$_.State -eq "Opened"} | select -First 1 | select ComputerName
$srvsend=$srvsmtp.computername
$EndDate = Get-Date
$EndDateMSG=(Get-Date).AddDays(+1)
$body = Get-Content $welcomemsg -Raw
$mbx=Search-AdminAuditLog -StartDate $StartDate -EndDate $EndDate  -ResultSize 1000 -Cmdlets New-Mailbox,Enable-Mailbox |select ObjectModified    
If ($mbx -ne $null)
{
$usrname=$mbx.ObjectModified
$usrname | % $username {"$_"| Get-User | Select Name} | out-null 
$Onlyname=$usrname | % $username {"$_"| Get-User | Select Name}
$usr=$Onlyname.name 
ForEach ($_ in $usr)
{
$sent=Get-MailboxServer -WarningAction SilentlyContinue | Get-MessageTrackingLog -ResultSize 1000 -Recipients  "$_@$dom" -Sender "$Sender" -Start $StartDate -End $EndDateMSG -ErrorAction SilentlyContinue | ? {$_.EventId -eq "DELIVER"} | sort-object -property subject | Select-Object | ? {$_.MessageSubject -eq "$sub"}
    if ($sent -eq $null)
        {
            Send-MailMessage -From "$Sender" -To "$_@$dom" -Subject "$Sub" -Body $body -BodyAsHtml -SmtpServer "$srvsend" -Port 25 -UseSsl:$false
            Write-Host -ForegroundColor Green "A Messages sent to $_"
        }
            Else 
                {
                   Write-Host -ForegroundColor DarkCyan "A Messages was already sent to $_"
                }
                    }
                        }
Else 
{
Write-Host -ForegroundColor Red "There are no new mailboxes"
Exit
}