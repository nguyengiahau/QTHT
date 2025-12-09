<#
    Client01_JoinDomain.ps1
    - Bật DHCP cho card đang kết nối
    - Join domain hotensv.vn với tên máy Client01
#>

param(
    [string]$DomainName = "hotensv.vn",
    [string]$NewName    = "Client01",
    [string]$DomainNetBIOS = "HOTENSV"
)

Write-Host "=== 1. Lấy card mạng đang Up ==="
$adapter = Get-NetAdapter | Where-Object Status -eq "Up" | Sort-Object ifIndex | Select-Object -First 1

if (-not $adapter) {
    Write-Error "Không tìm thấy card mạng nào đang hoạt động."
    exit 1
}

Write-Host "Sử dụng card: $($adapter.Name)"

Write-Host "=== 2. Bật DHCP cho IPv4 (nhận IP từ DC1 - DHCP) ==="
Set-NetIPInterface -InterfaceIndex $adapter.IfIndex -Dhcp Enabled -ErrorAction SilentlyContinue

# Chờ vài giây để client nhận IP từ DHCP
Start-Sleep -Seconds 10

Write-Host "=== 3. Join domain $DomainName với tên máy $NewName ==="
$domainUser = "$DomainNetBIOS\Administrator"
$pwd = Read-Host "Nhập mật khẩu cho tài khoản $domainUser" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential($domainUser,$pwd)

Add-Computer `
  -DomainName $DomainName `
  -Credential $cred `
  -NewName $NewName `
  -Force `
  -Restart
