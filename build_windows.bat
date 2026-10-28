@echo off
setlocal enabledelayedexpansion
title mone_task_app - Windows Auto Builder

REM ============================================================
REM   Avtomatik Windows release builder.
REM   Ikki marta bosib ishga tushiring - qolganini o'zi qiladi.
REM
REM   ESLATMA (tekshirilgan ishlaydigan ketma-ketlik):
REM     1) Loyiha ASCII papkaga (C:\monetaskbuild) ko'chiriladi, chunki
REM        Cyrillic user-papka (Administrator) path da release build buziladi.
REM     2) flutter pub get + flutter build windows --release.
REM     3) Release bundle zip qilinib, shu papkaga qo'yiladi.
REM     4) Zip GitHub Releases'ga chiqariladi (avto-update manbasi).
REM ============================================================

REM --- Manba papka (oxiridagi backslash olib tashlanadi, robocopy uchun) ---
set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"

set "DEST=C:\monetaskbuild"

echo.
echo ============================================================
echo   mone_task_app  -  Windows Auto Builder
echo ============================================================
echo   Manba : %SRC%
echo   Build : %DEST%
echo ============================================================
echo.

REM --- Versiyani pubspec.yaml dan o'qish (version: 0.4.9+49) ---
set "VERSION="
for /f "tokens=2 delims= " %%a in ('findstr /b "version:" "%SRC%\pubspec.yaml"') do set "VERFULL=%%a"
for /f "tokens=1 delims=+" %%b in ("%VERFULL%") do set "VERSION=%%b"
if "%VERSION%"=="" set "VERSION=dev"
echo   Versiya : %VERSION%
echo.

REM --- flutter borligini tekshirish ---
where flutter >nul 2>nul
if errorlevel 1 (
    echo [XATO] 'flutter' PATH da topilmadi. Flutter SDK ni PATH ga qo'shing.
    goto :fail
)

REM --- 0/4: git pull (oxirgi o'zgarishlarni olish; xato bo'lsa davom etadi) ---
where git >nul 2>nul
if errorlevel 1 (
    echo [OGOHLANTIRISH] 'git' topilmadi - pull o'tkazib yuborildi.
) else (
    echo [0/4] git pull...
    pushd "%SRC%"
    git pull
    if errorlevel 1 (
        echo [OGOHLANTIRISH] git pull muvaffaqiyatsiz ^(lokal o'zgarishlar bo'lishi mumkin^) - mavjud kod bilan davom etiladi.
    )
    popd
)
echo.

REM --- 1/4: ASCII papkaga ko'chirish (build, .git, .dart_tool, ephemeral va eski zip tashlanadi) ---
REM ESLATMA: "ephemeral" ichida .plugin_symlinks bor - u ko'chirilsa flutter
REM yangi symlink yarata olmay "errno = 183" xatosi bilan yiqiladi.
echo [1/4] Loyiha %DEST% ga ko'chirilmoqda...
if not exist "%DEST%" mkdir "%DEST%"
robocopy "%SRC%" "%DEST%" /E /XD "build" ".git" ".dart_tool" "ephemeral" /XF "*.zip" /NFL /NDL /NJH /NJS /NP /R:1 /W:1 >nul
REM robocopy 0..7 = muvaffaqiyat, 8+ = xato
if %errorlevel% geq 8 (
    echo [XATO] Nusxa ko'chirishda xatolik ^(robocopy=%errorlevel%^).
    goto :fail
)

REM --- DEST da oldingi ko'chirishdan qolgan eski ephemeral papkalarni tozalash ---
if exist "%DEST%\windows\flutter\ephemeral" rd /s /q "%DEST%\windows\flutter\ephemeral"
if exist "%DEST%\linux\flutter\ephemeral" rd /s /q "%DEST%\linux\flutter\ephemeral"
if exist "%DEST%\macos\Flutter\ephemeral" rd /s /q "%DEST%\macos\Flutter\ephemeral"

REM --- Oyna sarlavhasiga versiya qo'shish (faqat build nusxasida) ---
REM     "mone_task_app" -> "mone_task_app v0.5.7"
echo [+] Oyna sarlavhasiga versiya yozilmoqda: mone_task_app v%VERSION%
powershell -NoProfile -Command "$f='%DEST%\windows\runner\main.cpp'; (Get-Content $f -Raw) -replace 'L\"mone_task_app\"', ('L\"mone_task_app v%VERSION%\"') | Set-Content $f -Encoding UTF8"

REM --- ASCII papkaga o'tib build ---
pushd "%DEST%"

echo [2/4] flutter pub get...
call flutter pub get
if errorlevel 1 (
    echo [XATO] flutter pub get muvaffaqiyatsiz.
    popd
    goto :fail
)

echo [3/4] flutter build windows --release  ^(biroz vaqt oladi^)...
call flutter build windows --release
if errorlevel 1 (
    echo [XATO] Build muvaffaqiyatsiz tugadi.
    popd
    goto :fail
)
popd

REM --- 4/4: Release bundle ni zip qilish ---
set "RELDIR=%DEST%\build\windows\x64\runner\Release"
if not exist "%RELDIR%\mone_task_app.exe" (
    echo [XATO] Release bundle topilmadi: %RELDIR%
    goto :fail
)

REM --- Visual C++ runtime DLL larini bundle ga qo'shish (boshqa kompyuterda
REM     VC++ Redistributable bo'lmasa ham dastur ishlashi uchun) ---
echo [+] VC++ runtime DLL lari tekshirilmoqda...
for %%d in (msvcp140.dll msvcp140_1.dll msvcp140_2.dll vcruntime140.dll vcruntime140_1.dll) do (
    if not exist "%RELDIR%\%%d" (
        if exist "%SystemRoot%\System32\%%d" (
            copy /y "%SystemRoot%\System32\%%d" "%RELDIR%\" >nul
            echo     + %%d System32 dan nusxalandi
        )
    )
)
REM Majburiy uchtasi bo'lmasa build yaroqsiz - to'xtatamiz
for %%d in (msvcp140.dll vcruntime140.dll vcruntime140_1.dll) do (
    if not exist "%RELDIR%\%%d" (
        echo [XATO] %%d topilmadi - bundle boshqa kompyuterda ishlamaydi.
        goto :fail
    )
)

set "ZIPNAME=mone_task_app_v%VERSION%_windows.zip"
echo [4/4] Zip yaratilmoqda: %ZIPNAME%
if exist "%SRC%\%ZIPNAME%" del /f /q "%SRC%\%ZIPNAME%"
powershell -NoProfile -Command "Compress-Archive -Path '%RELDIR%\*' -DestinationPath '%SRC%\%ZIPNAME%' -Force"
if errorlevel 1 (
    echo [XATO] Zip yaratishda xatolik.
    goto :fail
)

REM --- 5/5: GitHub Releases'ga chiqarish (Windows avto-update manbasi) ---
REM     Desktop\Release nusxalashdan OLDIN - u yerdan ilova ochiq bo'lsa
REM     nusxalash xatosi publish'ni to'sib qo'ymasligi kerak.
echo [5/5] GitHub Releases'ga chiqarilmoqda (v%VERSION%)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SRC%\publish_release.ps1" -Version "%VERSION%" -Zip "%SRC%\%ZIPNAME%"
if errorlevel 1 (
    echo [OGOHLANTIRISH] Release chiqarilmadi - yuqoridagi xabarga qarang.
    echo   Avto-update ishlashi uchun release chiqishi SHART.
)

REM --- Release bundle ni Desktop\Release_mone_task_app papkaga nusxalash (ixtiyoriy) ---
set "OUTDIR=%USERPROFILE%\Desktop\Release_mone_task_app"
echo [+] Release papkaga nusxalanmoqda: %OUTDIR%
robocopy "%RELDIR%" "%OUTDIR%" /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1 >nul
if %errorlevel% geq 8 (
    echo [OGOHLANTIRISH] Release papkaga nusxalab bo'lmadi ^(robocopy=%errorlevel%^) - ehtimol ilova o'sha papkadan ochiq. GitHub release baribir chiqdi.
)

echo.
echo ============================================================
echo   TAYYOR!
echo   Bundle : %RELDIR%
echo   Zip    : %SRC%\%ZIPNAME%
echo   Release: %OUTDIR%
echo ============================================================
echo.
if not defined UZ_BOT pause
exit /b 0

:fail
echo.
echo ============================================================
echo   BUILD TUGAMADI - yuqoridagi xatoga qarang.
echo ============================================================
echo.
if not defined UZ_BOT pause
exit /b 1
