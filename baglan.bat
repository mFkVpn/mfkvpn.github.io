@echo off
chcp 65001 >nul
title mFkVpN - Baglanti Yoneticisi
echo ========================================================
echo   mFkVpN Baglanti Yoneticisi (Helsinki Node)
echo ========================================================
echo.

powershell -NoProfile -Command "if (!(Get-VpnConnection -Name 'mFkVpN' -ErrorAction SilentlyContinue)) { exit 1 }" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [UYARI] 'mFkVpN' adli baglanti profili Windows ag ayarlarinda bulunamadi!
    echo Otomatik kurulum baslatiliyor (Yonetici izni istenebilir)...
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_windows_vpn.ps1"
    echo.
)

echo Baglanti penceresi aciliyor. 
echo Ilk baglantida kullanici bilgilerinizi girip 'Beni Hatirla' kutusunu isaretleyin.
echo ========================================================
rasphone -d "mFkVpN"
