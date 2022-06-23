#Get server and key
param($server, $key, $tls)
# Download latest release from github
if($PSVersionTable.PSVersion.Major -lt 5){
    Write-Host "Require PS >= 5,your PSVersion:"$PSVersionTable.PSVersion.Major -BackgroundColor DarkGreen -ForegroundColor White
    Write-Host "Refer to the community article and install manually! https://nyko.me/2020/12/13/nezha-windows-client.html" -BackgroundColor DarkRed -ForegroundColor Green
    exit
}
$agentrepo = "xos/probe"
$nssmrepo = "nezhahq/nssm-backup"
#  x86 or x64
if ([System.Environment]::Is64BitOperatingSystem) {
    $file = "probe-agent_windows_amd64.zip"
}
else {
    $file = "probe-agent_windows_386.zip"
}
$agentreleases = "https://api.github.com/repos/$agentrepo/releases"
$nssmreleases = "https://api.github.com/repos/$nssmrepo/releases"
#重复运行自动更新
if (Test-Path "C:\probe") {
    Write-Host "Probe monitoring already exists, delete and reinstall" -BackgroundColor DarkGreen -ForegroundColor White
    C:/probe/nssm.exe stop probe
    C:/probe/nssm.exe remove probe
    Remove-Item "C:\probe" -Recurse
}
#TLS/SSL
Write-Host "Determining latest Probe release" -BackgroundColor DarkGreen -ForegroundColor White
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$agenttag = (Invoke-WebRequest -Uri $agentreleases -UseBasicParsing | ConvertFrom-Json)[0].tag_name
$nssmtag = (Invoke-WebRequest -Uri $nssmreleases -UseBasicParsing | ConvertFrom-Json)[0].tag_name
#Region判断
$ipapi= Invoke-RestMethod  -Uri "https://api.myip.com/" -UserAgent "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/535.1 (KHTML, like Gecko) Chrome/14.0.835.163 Safari/535.1"
$region=$ipapi.cc
echo $ipapi
if($region -ne "CN"){
$download = "https://github.com/$agentrepo/releases/download/$agenttag/$file"
$nssmdownload="https://github.com/$nssmrepo/releases/download/$nssmtag/nssm.zip"
Write-Host "Location:$region,connect directly!" -BackgroundColor DarkRed -ForegroundColor Green
}else{
$download = "https://ghproxy.com/github.com/$agentrepo/releases/download/$agenttag/$file"
$nssmdownload="https://dn-dao-github-mirror.daocloud.io/$nssmrepo/releases/download/$nssmtag/nssm.zip"
Write-Host "Location:CN,use mirror address" -BackgroundColor DarkRed -ForegroundColor Green
}
echo $download
echo $nssmdownload
Invoke-WebRequest $download -OutFile "C:\probe.zip"
#使用nssm安装服务
Invoke-WebRequest $nssmdownload -OutFile "C:\nssm.zip"
#解压
Expand-Archive "C:\probe.zip" -DestinationPath "C:\temp" -Force
Expand-Archive "C:\nssm.zip" -DestinationPath "C:\temp" -Force
if (!(Test-Path "C:\probe")) { New-Item -Path "C:\probe" -type directory }
#整理文件
Move-Item -Path "C:\temp\probe-agent.exe" -Destination "C:\probe\probe-agent.exe"
if ($file = "probe-agent_windows_amd64.zip") {
    Move-Item -Path "C:\temp\nssm-2.24\win64\nssm.exe" -Destination "C:\probe\nssm.exe"
}
else {
    Move-Item -Path "C:\temp\nssm-2.24\win32\nssm.exe" -Destination "C:\probe\nssm.exe"
}
#清理垃圾
Remove-Item "C:\probe.zip"
Remove-Item "C:\nssm.zip"
Remove-Item "C:\temp" -Recurse
#安装部分
C:\probe\nssm.exe install probe C:\probe\probe-agent.exe -s $server -p $key $tls -d 
C:\probe\nssm.exe start probe
#enjoy
Write-Host "Enjoy It!" -BackgroundColor DarkGreen -ForegroundColor Red
