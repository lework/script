
$PasswordString = "Ac@123356"
$RDCManSource = (Get-ChildItem .\RDCMan.exe -Recurse).FullName
$RDGFile = (Get-ChildItem .\test.rdg -Recurse).FullName

If (!$RDCManSource)
{
    Write-Error "RDCMan test-erp.exe not found"
    Start-Sleep -Seconds 10
    Exit
}
else
{
    try
    {
        $Assembly = [Reflection.Assembly]::LoadFile($RDCManSource)
    }
    catch
    {
        $_.Exception.Message.ToString();
        Write-Host "Catch"; Start-Sleep -Seconds 10; Exit
    }
    try { Import-Module $Assembly }
    catch
    {
        $_.Exception.Message.ToString();
        Write-Host "Import Exception"; Start-Sleep -Seconds 10; exit }
}

If ($RDGFile)
{
    
    $EncryptionSettings = New-Object -TypeName RdcMan.EncryptionSettings
    $Password = [RdcMan.Encryption]::EncryptString($PasswordString , $EncryptionSettings)

    try
    {
       $Data = Get-Content $RDGFile
    }
    catch
    {
        $_.Exception.Message.ToString();
        Write-Host "Import Exception";
        exit 
    }
    $newContent = $Data -replace '{{PWD}}', $Password
    $newContent | Set-Content $RDGFile
    
    Write-Host "CreateShortcut"
    $shell = New-Object -ComObject ("WScript.Shell")
    $shortcut = $shell.CreateShortcut("$HOME\Desktop\test.lnk")
    $shortcut.TargetPath = $RDCManSource
    $shortcut.Save()
    
    Write-Host "open test-erp"
    Start-Process -FilePath $RDCManSource -ArgumentList $RDGFile

    Start-Sleep -Seconds 5
    Write-Host "ok"; exit
}
else
{
    Write-Error "RDGFile test-erp.rdg not found"
    Start-Sleep -Seconds 10
    Exit
}