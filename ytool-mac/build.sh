#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "🔨 Compilando..."
swift build -c release

echo "📦 Empacotando..."
rm -rf YToolMac.app ~/Desktop/YToolMac.app
mkdir -p YToolMac.app/Contents/{MacOS,Resources}
cp .build/release/YToolMac YToolMac.app/Contents/MacOS/
chmod +x YToolMac.app/Contents/MacOS/YToolMac
cp -r .build/release/YToolMac_YToolMac.bundle/bin YToolMac.app/Contents/Resources/ 2>/dev/null || true
[ -f AppIcon.icns ] && cp AppIcon.icns YToolMac.app/Contents/Resources/

cat > YToolMac.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>YToolMac</string>
    <key>CFBundleIdentifier</key><string>com.ytool.mac</string>
    <key>CFBundleName</key><string>YTool</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

cp -r YToolMac.app ~/Desktop/
echo "✅ YToolMac.app no Desktop"
open ~/Desktop/YToolMac.app
