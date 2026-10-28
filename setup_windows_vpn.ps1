# mFkVpN Windows Yerleşik IKEv2 Kurulum ve Bağlantı Aracı
$ErrorActionPreference = "Stop"

# Yönetici Yetkisi Kontrolü ve Otomatik Yükseltme
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Bu kurulum betiği Yönetici (Administrator) yetkisi gerektirir."
    Write-Host "Yönetici izni talep ediliyor..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"") -Verb RunAs
    exit
}

$VpnName = "mFkVpN"
$Server = "46.224.62.213.sslip.io"

Write-Host ">>> mFkVpN Windows IKEv2 Yapılandırması Başlatılıyor..." -ForegroundColor Cyan

$existing = Get-VpnConnection -Name $VpnName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[-] Eski $VpnName bağlantısı kaldırılıyor..." -ForegroundColor Yellow
    Remove-VpnConnection -Name $VpnName -Force
}

Write-Host "[+] $VpnName yerleşik VPN bağlantısı ekleniyor ($Server)..." -ForegroundColor Green
Add-VpnConnection -Name $VpnName `
    -ServerAddress $Server `
    -TunnelType Ikev2 `
    -AuthenticationMethod Eap `
    -EncryptionLevel Required `
    -RememberCredential

Set-VpnConnection -Name $VpnName -SplitTunneling $false

# EAP-MSCHAPv2 (Kullanıcı Adı & Parola) Yapılandırması
$eapXml = @"
<EapHostConfig xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
    <EapMethod>
        <Type xmlns="http://www.microsoft.com/provisioning/EapCommon">26</Type>
        <VendorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorId>
        <VendorType xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorType>
        <AuthorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</AuthorId>
    </EapMethod>
    <Config xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
        <Eap xmlns="http://www.microsoft.com/provisioning/BaseEapConnectionPropertiesV1">
            <Type>26</Type>
            <EapType xmlns="http://www.microsoft.com/provisioning/MsChapV2ConnectionPropertiesV1">
                <UseWinLogonCredentials>false</UseWinLogonCredentials>
            </EapType>
        </Eap>
    </Config>
</EapHostConfig>
"@

$xmlDoc = [xml]$eapXml
Set-VpnConnection -Name $VpnName -EapConfigXmlStream $xmlDoc
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  mFkVpN BAŞARIYLA WINDOWS AĞ AYARLARINA EKLENDİ!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Nasıl Bağlanırsın?" -ForegroundColor Yellow
Write-Host "1. Sağ alttaki Wi-Fi / Ağ simgesine tıkla." -ForegroundColor White
Write-Host "2. Listeden 'mFkVpN' seç ve 'Bağlan' butonuna bas." -ForegroundColor White
Write-Host "3. Sunucu yöneticinizin belirlediği Kullanıcı Adı ve Parolanızı girin." -ForegroundColor Cyan
Write-Host ""
Write-Host "Veya terminalden bağlanmak için:" -ForegroundColor Yellow
Write-Host 'rasdial "mFkVpN" <kullanici_adi> <parola>' -ForegroundColor Gray
Write-Host ""
