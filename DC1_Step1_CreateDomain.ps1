<# 
    DC1_Step1_CreateDomain.ps1
    - Đặt tên máy: DC1
    - Cấu hình IP:
        + NIC 1 (LAN1): 192.168.1.1/24, DNS 127.0.0.1
        + NIC 2 (LANSG): 192.168.10.1/24 + 192.168.10.20/24, DNS 192.168.1.1
    - Cài AD DS + DNS
    - Tạo forest/domain: hotensv.vn (NetBIOS: HOTENSV)
#>

$domainName  = "nguyengiahau.vn"
$netbiosName = "NGUYENGIAHAU"

Write-Host "=== B1: Đổi tên máy thành DC1 ==="
Rename-Computer -NewName "DC1" -Force -PassThru

Write-Host "=== B2: Lấy 2 card mạng đang up để cấu hình IP (giả định có đúng 2 card) ==="
$adapters = Get-NetAdapter | Where-Object Status -eq "Up" | Sort-Object ifIndex

if ($adapters.Count -lt 2) {
    Write-Error "Không tìm đủ 2 card mạng. Hãy kiểm tra lại cấu hình NIC (VirtualBox, v.v...)."
    exit 1
}

$lan1   = $adapters[0]   # dải 192.168.1.0
$langsg = $adapters[1]   # dải 192.168.10.0

Write-Host "Cấu hình LAN1 ($($lan1.Name)) = 192.168.1.1/24, DNS 127.0.0.1"
New-NetIPAddress -InterfaceIndex $lan1.IfIndex -IPAddress "192.168.1.1" -PrefixLength 24 -DefaultGateway $null -ErrorAction SilentlyContinue | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $lan1.IfIndex -ServerAddresses "127.0.0.1"

Write-Host "Cấu hình LANSG ($($langsg.Name)) = 192.168.10.1 và 192.168.10.20 /24, DNS 192.168.1.1"
New-NetIPAddress -InterfaceIndex $langsg.IfIndex -IPAddress "192.168.10.1" -PrefixLength 24 -DefaultGateway $null -ErrorAction SilentlyContinue | Out-Null
New-NetIPAddress -InterfaceIndex $langsg.IfIndex -IPAddress "192.168.10.20" -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $langsg.IfIndex -ServerAddresses "192.168.1.1"

Write-Host "=== B3: Cài AD DS + DNS ==="
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools

Write-Host "=== B4: Tạo forest/domain hotensv.vn ==="
$dsrmPwd = Read-Host "Nhập mật khẩu DSRM (Safe Mode) cho DC1" -AsSecureString

Install-ADDSForest `
  -DomainName $domainName `
  -DomainNetbiosName $netbiosName `
  -SafeModeAdministratorPassword $dsrmPwd `
  -InstallDns `
  -Force
# Sau lệnh này server sẽ tự reboot. Sau reboot, đăng nhập bằng tài khoản domain (HOTENSV\Administrator) và chạy Step2.
