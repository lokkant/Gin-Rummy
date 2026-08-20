@echo off
setlocal

set "PROJECT_DIR=%~dp0"
set "LOVE_DIR=C:\Program Files\LOVE"
set "BUILD_DIR=%PROJECT_DIR%build"
set "APP_NAME=GinRummy"

echo Building %APP_NAME%...

if not exist "%LOVE_DIR%\love.exe" (
    echo ERROR: love.exe not found at "%LOVE_DIR%". Edit LOVE_DIR at the top of this script.
    exit /b 1
)

if exist "%BUILD_DIR%" rd /s /q "%BUILD_DIR%" 2>nul
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

echo Packaging sources into %APP_NAME%.love...
powershell -NoProfile -Command "$items = Get-ChildItem -Path '%PROJECT_DIR%' -Exclude '.idea','.git','build','*.bat'; Compress-Archive -Path $items.FullName -DestinationPath '%BUILD_DIR%\%APP_NAME%.zip' -Force; Move-Item '%BUILD_DIR%\%APP_NAME%.zip' '%BUILD_DIR%\%APP_NAME%.love' -Force"

if not exist "%BUILD_DIR%\%APP_NAME%.love" (
    echo ERROR: failed to create .love archive.
    exit /b 1
)

echo Fusing with love.exe...
copy /b "%LOVE_DIR%\love.exe"+"%BUILD_DIR%\%APP_NAME%.love" "%BUILD_DIR%\%APP_NAME%.exe" >nul

echo Copying dependencies...
copy /y "%LOVE_DIR%\*.dll" "%BUILD_DIR%\" >nul

del "%BUILD_DIR%\%APP_NAME%.love"

echo.
echo Done. Output: %BUILD_DIR%\%APP_NAME%.exe
echo Run client: %APP_NAME%.exe
echo Run server: %APP_NAME%.exe --server

endlocal
