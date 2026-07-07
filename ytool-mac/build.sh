#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "🔨 Compilando (universal: Intel + Apple Silicon)..."
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BUILD_DIR=".build/apple/Products/Release"
else
    echo "⚠️  Build universal falhou — compilando só para esta arquitetura"
    swift build -c release
    BUILD_DIR=".build/release"
fi

echo "📦 Empacotando..."
rm -rf YToolMac.app ~/Desktop/YToolMac.app
mkdir -p YToolMac.app/Contents/{MacOS,Resources}
cp "$BUILD_DIR/YToolMac" YToolMac.app/Contents/MacOS/
chmod +x YToolMac.app/Contents/MacOS/YToolMac
# O layout interno do bundle muda entre build normal e universal
if [ -d "$BUILD_DIR/YToolMac_YToolMac.bundle/Contents/Resources/bin" ]; then
    cp -r "$BUILD_DIR/YToolMac_YToolMac.bundle/Contents/Resources/bin" YToolMac.app/Contents/Resources/
elif [ -d "$BUILD_DIR/YToolMac_YToolMac.bundle/bin" ]; then
    cp -r "$BUILD_DIR/YToolMac_YToolMac.bundle/bin" YToolMac.app/Contents/Resources/
else
    echo "❌ Pasta bin não encontrada no bundle — app NÃO ficará autossuficiente"
    exit 1
fi
chmod +x YToolMac.app/Contents/Resources/bin/* 2>/dev/null || true
[ -f AppIcon.icns ] && cp AppIcon.icns YToolMac.app/Contents/Resources/

cat > YToolMac.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>YToolMac</string>
    <key>CFBundleIdentifier</key><string>com.ytool.mac</string>
    <key>CFBundleName</key><string>YTool</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
EOF

echo "🔏 Assinando (ad-hoc — necessário para rodar em Apple Silicon)..."
codesign --force --deep --sign - YToolMac.app

cp -r YToolMac.app ~/Desktop/
echo "✅ YToolMac.app no Desktop (autossuficiente: yt-dlp e ffmpeg inclusos)"
open ~/Desktop/YToolMac.app
