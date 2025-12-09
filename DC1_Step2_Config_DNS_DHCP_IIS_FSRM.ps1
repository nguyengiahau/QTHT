<#
    DC1_Step2_Config_DNS_DHCP_IIS_FSRM.ps1
    - DNS: bản ghi A, CNAME cho DC1 và portal
    - DHCP: scope 192.168.10.0/24, exclude 10.1–10.20, options Domain & DNS
    - IIS: website "Portal" → C:\Intranet\Portal_Page, host header portal.hotensv.vn
    - FSRM: quota, file screen, report tuần
#>

param(
    [string]$DomainName = "nguyengiahau.vn",
    [string]$FileRoot   = "D:\nguyengiahau_Data",
    [string]$AdminMail  = "admin@nguyengiahau.vn"
)

Write-Host "=== Import module ==="
Import-Module DHCPServer -ErrorAction SilentlyContinue
Import-Module WebAdministration -ErrorAction SilentlyContinue
Import-Module FileServerResourceManager -ErrorAction SilentlyContinue

# ---------- 1. DNS ----------
Write-Host "=== 1. Cấu hình DNS record ==="

# Bản ghi A cho File Server: DC1.hotensv.vn -> 192.168.10.20
Add-DnsServerResourceRecordA `
  -Name "DC1" `
  -ZoneName $DomainName `
  -IPv4Address "192.168.10.20" `
  -AllowUpdateAny `
  -TimeToLive 01:00:00

# CNAME portal.hotensv.vn -> DC1.hotensv.vn
Add-DnsServerResourceRecordCName `
  -Name "portal" `
  -ZoneName $DomainName `
  -HostNameAlias ("DC1." + $DomainName)

# ---------- 2. DHCP ----------
Write-Host "=== 2. Cài và cấu hình DHCP ==="
Install-WindowsFeature DHCP -IncludeManagementTools

# Authorize DHCP trong AD
Add-DhcpServerInDC -DnsName ("DC1." + $DomainName) -IpAddress "192.168.1.1"

# Scope 192.168.10.0/24
Add-DhcpServerv4Scope `
    -Name "192.168.10.0 DHCP - LANSG" `
    -StartRange 192.168.10.21 `
    -EndRange   192.168.10.254 `
    -SubnetMask 255.255.255.0 `
    -State Active

# Exclusion 192.168.10.1 – 192.168.10.20
Add-DhcpServerv4ExclusionRange -ScopeId 192.168.10.0 -StartRange 192.168.10.1 -EndRange 192.168.10.20

# Option: Default Gateway, DNS Domain, DNS Server
Set-DhcpServerv4OptionValue -ScopeId 192.168.10.0 -Router   192.168.10.1
Set-DhcpServerv4OptionValue -ScopeId 192.168.10.0 -DnsDomain $DomainName -DnsServer 192.168.1.1

# ---------- 3. IIS / Website Portal ----------
Write-Host "=== 3. Cài Web Server (IIS) và tạo website Portal ==="
Install-WindowsFeature Web-Server -IncludeManagementTools

# Thư mục web
New-Item -Path "C:\Intranet\Portal_Page" -ItemType Directory -Force | Out-Null

# Tạo file index.html đơn giản (có MSSV của bạn)
@"
<html>
<head><title>Portal - $DomainName</title></head>
<body>
    <h1>Intranet Portal - $DomainName</h1>
    <p>Server: DC1 ($env:COMPUTERNAME)</p>
    <p>Sinh viên: Nguyen Gia Hau - MSSV 2224802010349</p>
</body>
</html>
"@ | Set-Content "C:\Intranet\Portal_Page\index.html" -Encoding UTF8

Import-Module WebAdministration

# Stop Default Web Site để tránh trùng port 80
if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
    Stop-Website "Default Web Site"
}

# Tạo website Portal
if (-not (Get-Website -Name "Portal" -ErrorAction SilentlyContinue)) {
    New-Website `
      -Name "Portal" `
      -PhysicalPath "C:\Intranet\Portal_Page" `
      -Port 80 `
      -HostHeader ("portal." + $DomainName) `
      -IPAddress "*"
}

# ---------- 4. FSRM (Quota, File Screen, Reports) ----------
Write-Host "=== 4. Cài đặt FSRM và cấu hình quản lý lưu trữ ==="
Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools

# 4.1 Thư mục phòng ban
New-Item -Path $FileRoot -ItemType Directory -Force | Out-Null
New-Item -Path (Join-Path $FileRoot "HR_Share")    -ItemType Directory -Force | Out-Null
New-Item -Path (Join-Path $FileRoot "Sales_Share") -ItemType Directory -Force | Out-Null

# 4.2 Quota template (HR 500MB, Sales 1GB)
Write-Host "Tạo quota template HR_500MB và Sales_1GB"

$hrQuotaTemplate = New-FsrmQuotaTemplate `
    -Name "HR_500MB" `
    -Description "HR share 500MB hard quota" `
    -Size 500MB `
    -SoftLimit:$false

$salesQuotaTemplate = New-FsrmQuotaTemplate `
    -Name "Sales_1GB" `
    -Description "Sales share 1GB hard quota" `
    -Size 1GB `
    -SoftLimit:$false

# Thêm threshold 85% với email action (mô hình chuẩn: New-FsrmAction -> New-FsrmQuotaThreshold -> Set-FsrmQuotaTemplate) :contentReference[oaicite:2]{index=2}
$hrEmailAction = New-FsrmAction Email `
    -MailTo $AdminMail `
    -Subject "HR_Share sử dụng vượt 85% quota" `
    -Body "Thư mục HR_Share trên DC1 đã vượt 85% hạn mức dung lượng."

$hrThreshold = New-FsrmQuotaThreshold -Percentage 85 -Action $hrEmailAction
Set-FsrmQuotaTemplate -Name "HR_500MB" -Threshold $hrThreshold | Out-Null

$salesEmailAction = New-FsrmAction Email `
    -MailTo $AdminMail `
    -Subject "Sales_Share sử dụng vượt 85% quota" `
    -Body "Thư mục Sales_Share trên DC1 đã vượt 85% hạn mức dung lượng."

$salesThreshold = New-FsrmQuotaThreshold -Percentage 85 -Action $salesEmailAction
Set-FsrmQuotaTemplate -Name "Sales_1GB" -Threshold $salesThreshold | Out-Null

# Áp quota cho thư mục
New-FsrmQuota -Path (Join-Path $FileRoot "HR_Share")    -Template "HR_500MB"  | Out-Null
New-FsrmQuota -Path (Join-Path $FileRoot "Sales_Share") -Template "Sales_1GB" | Out-Null

# 4.3 File groups cho audio/video và exe/torrent
Write-Host "Tạo File Groups cho Audio/Video và EXE/Torrent"
New-FsrmFileGroup -Name "AudioVideo_Block" -IncludePattern @("*.mp3","*.mp4","*.avi") | Out-Null
New-FsrmFileGroup -Name "Exe_Torrent_Monitor" -IncludePattern @("*.exe","*.torrent") | Out-Null

# 4.4 File screen chặn nhạc/video (Active Screening)
Write-Host "Tạo File Screen chặn nhạc/video trên $FileRoot"

$avEmail = New-FsrmAction Email `
    -MailTo $AdminMail `
    -Subject "Bị chặn lưu file giải trí" `
    -Body "Người dùng [Source Io Owner] đã bị chặn lưu file [Source File Path] trên server."

$avTemplate = New-FsrmFileScreenTemplate `
    -Name "Block_AudioVideo" `
    -IncludeGroup "AudioVideo_Block" `
    -Notification $avEmail `
    -Active

New-FsrmFileScreen -Path $FileRoot -Template "Block_AudioVideo" -Active | Out-Null  # mẫu dùng Template + Active giống tài liệu Microsoft/FSRM :contentReference[oaicite:3]{index=3}

# 4.5 File screen cho .exe và .torrent (log + email + message cho user)
Write-Host "Tạo File Screen cho EXE/Torrent (log, email, popup)"

$exeEvt = New-FsrmAction Event `
    -EventType Warning `
    -Body "Người dùng [Source Io Owner] lưu file bị cấm [Source File Path]."

$exeMail = New-FsrmAction Email `
    -MailTo $AdminMail `
    -Subject "Cảnh báo lưu file .exe/.torrent" `
    -Body "Người dùng [Source Io Owner] vừa lưu file [Source File Path] trên server."

$exeMsg = New-FsrmAction Command `
    -Command "cmd.exe" `
    -CommandParameters '/c msg * "Ban khong duoc luu file .exe hoac .torrent tren may chu file."' `
    -SecurityLevel LocalSystem

$exeTemplate = New-FsrmFileScreenTemplate `
    -Name "Block_Exe_Torrent" `
    -IncludeGroup "Exe_Torrent_Monitor" `
    -Notification @($exeEvt,$exeMail,$exeMsg) `
    -Active

New-FsrmFileScreen -Path $FileRoot -Template "Block_Exe_Torrent" -Active | Out-Null

# 4.6 Storage report weekly: LargeFiles, DuplicateFiles, FilesByOwner
Write-Host "Tạo Storage Report hàng tuần"

# Chủ nhật 00:00
$d = Get-Date "00:00"
$weeklyTask = New-FsrmScheduledTask -Time $d -Weekly @(Sunday)

# Report các file lớn, file trùng, dung lượng theo user
New-FsrmStorageReport `
  -Name "Weekly_Storage_Reports" `
  -Namespace @($FileRoot) `
  -Schedule $weeklyTask `
  -ReportType @("LargeFiles","DuplicateFiles","FilesByOwner") `
  -LargeFileMinimum 10MB | Out-Null

Write-Host ">>> DC1 đã cấu hình xong DNS, DHCP, IIS, FSRM cho bài TH5." -ForegroundColor Green
