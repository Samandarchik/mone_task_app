# ============================================================
#   Windows zip'ni GitHub Releases'ga chiqaradi (avto-update manbasi).
#   build_windows.bat oxirida avtomatik chaqiriladi.
#
#   Bir martalik sozlash:
#     1) https://github.com/settings/tokens -> "Generate new token (classic)"
#        -> "repo" huquqi bilan token yarating.
#     2) Tokenni shu faylga saqlang (faqat token, bitta qator):
#           %USERPROFILE%\.github_release_token
#   Repo (Samandarchik/mone_task_app_releases) bo'lmasa skript
#   o'zi PUBLIC repo yaratadi — ilova undan autentifikatsiyasiz yuklab oladi.
# ============================================================
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$Zip
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Owner = 'Samandarchik'
$Repo = 'mone_task_app_releases'
$TokenFile = Join-Path $env:USERPROFILE '.github_release_token'

if (-not (Test-Path $TokenFile)) {
    Write-Host ''
    Write-Host '[PUBLISH O''TKAZILDI] GitHub token topilmadi:' -ForegroundColor Yellow
    Write-Host "    $TokenFile" -ForegroundColor Yellow
    Write-Host '  1) https://github.com/settings/tokens -> classic token, "repo" huquqi bilan'
    Write-Host "  2) Tokenni yuqoridagi faylga saqlang (bitta qator)"
    Write-Host '  Shundan keyin build avtomatik release chiqaradi.'
    exit 1
}
$Token = (Get-Content $TokenFile -Raw).Trim()
$Headers = @{
    Authorization = "token $Token"
    Accept        = 'application/vnd.github+json'
    'User-Agent'  = 'mone-task-app-builder'
}

$Api = "https://api.github.com"
$Tag = "v$Version"
$ZipName = [IO.Path]::GetFileName($Zip)

# --- Repo mavjudligini tekshirish; yo'q bo'lsa public repo yaratish ---
try {
    Invoke-RestMethod -Headers $Headers -Uri "$Api/repos/$Owner/$Repo" | Out-Null
} catch {
    Write-Host "[+] Repo topilmadi - yaratilmoqda: $Owner/$Repo (public)"
    $body = @{
        name        = $Repo
        description = 'mone_task_app Windows releases (auto-update)'
        private     = $false
        auto_init   = $true
    } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Headers $Headers -Uri "$Api/user/repos" `
        -ContentType 'application/json' -Body $body | Out-Null
    Start-Sleep -Seconds 2
}

# --- Shu tag bilan eski release bo'lsa o'chirish (qayta build holati) ---
try {
    $old = Invoke-RestMethod -Headers $Headers `
        -Uri "$Api/repos/$Owner/$Repo/releases/tags/$Tag"
    Write-Host "[+] Eski $Tag release o'chirilmoqda (qayta chiqarish)..."
    Invoke-RestMethod -Method Delete -Headers $Headers `
        -Uri "$Api/repos/$Owner/$Repo/releases/$($old.id)" | Out-Null
    try {
        Invoke-RestMethod -Method Delete -Headers $Headers `
            -Uri "$Api/repos/$Owner/$Repo/git/refs/tags/$Tag" | Out-Null
    } catch { }
} catch { }

# --- Release yaratish ---
# Avval DRAFT sifatida: draft "latest" hisoblanmaydi. Aks holda release zip
# yuklanishidan ~20 s oldin ko'rinib qolardi va shu oraliqda tekshirgan
# ilovalar yo'q zip'ni yuklashga urinib "Yuklab olishda xatolik" berardi.
Write-Host "[+] Release yaratilmoqda: $Tag"
$relBody = @{
    tag_name = $Tag
    name     = $Tag
    body     = "mone_task_app Windows $Version"
    draft    = $true
} | ConvertTo-Json
$release = Invoke-RestMethod -Method Post -Headers $Headers `
    -Uri "$Api/repos/$Owner/$Repo/releases" `
    -ContentType 'application/json' -Body $relBody

# --- Zip'ni asset sifatida yuklash ---
Write-Host "[+] Zip yuklanmoqda: $ZipName ($([math]::Round((Get-Item $Zip).Length/1MB,1)) MB)..."
$uploadUrl = "https://uploads.github.com/repos/$Owner/$Repo/releases/$($release.id)/assets?name=$ZipName"
Invoke-RestMethod -Method Post -Uri $uploadUrl `
    -Headers @{ Authorization = "token $Token"; 'User-Agent' = 'mone-task-app-builder' } `
    -ContentType 'application/zip' -InFile $Zip | Out-Null

# --- Zip joyida — endi e'lon qilamiz (shu paytdan "latest" bo'ladi) ---
Write-Host "[+] Release e'lon qilinmoqda: $Tag"
Invoke-RestMethod -Method Patch -Headers $Headers `
    -Uri "$Api/repos/$Owner/$Repo/releases/$($release.id)" `
    -ContentType 'application/json' -Body (@{ draft = $false } | ConvertTo-Json) | Out-Null

Write-Host ''
Write-Host "[OK] Release chiqdi: https://github.com/$Owner/$Repo/releases/tag/$Tag" -ForegroundColor Green
Write-Host '     Endi barcha Windows kompyuterlarda ilova o''zi yangilanadi.' -ForegroundColor Green
exit 0
