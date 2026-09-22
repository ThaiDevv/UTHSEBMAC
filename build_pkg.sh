#!/bin/bash
set -e

echo "=========================================================="
echo "🍎 Bắt đầu quy trình Build & Đóng gói UTHSEB Setup PKG (Full AI Edition)"
echo "=========================================================="

APP_NAME="UTH SEB.app"
BIN_NAME="UTHSEBMac"
PKG_NAME="UTHSEB-Setup-1.0.4.pkg"
BUNDLE_ID="vn.edu.uth.seb.mac"
VERSION="1.0.4"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/root/Applications/$APP_NAME"

# 1. Dọn dẹp thư mục build cũ
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 2. Biên dịch Swift Release
echo "🔨 [1/4] Đang biên dịch Swift Release..."
if [ "$(uname)" = "Darwin" ]; then
    swift build -c release
    
    # Tìm file binary thực thi
    DEFAULT_BIN_PATH="$(swift build -c release --show-bin-path)/$BIN_NAME"
    if [ -f "$DEFAULT_BIN_PATH" ]; then
        BINARY_PATH="$DEFAULT_BIN_PATH"
    else
        BINARY_PATH=$(find .build -type f -name "$BIN_NAME" -perm +111 2>/dev/null | head -n 1)
        if [ -z "$BINARY_PATH" ]; then
            BINARY_PATH=$(find .build -type f -name "$BIN_NAME" | head -n 1)
        fi
    fi
    echo "Found binary at: $BINARY_PATH"
else
    echo "⚠️ Lưu ý: Bạn đang chạy trên Linux. Lệnh pkgbuild/productbuild của Apple yêu cầu môi trường macOS."
    echo "   Bạn có thể chạy script này trên macOS hoặc dùng GitHub Actions."
    exit 1
fi

# 3. Tạo cấu trúc macOS App Bundle
echo "📦 [2/4] Đang tạo App Bundle ($APP_NAME)..."
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$BIN_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$BIN_NAME"

cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

if [ -d "$ROOT_DIR/Resources" ]; then
    cp -R "$ROOT_DIR/Resources/"* "$APP_DIR/Contents/Resources/"
fi

# 4. Ký mã giả lập (Ad-hoc Code Signing để macOS cho phép khởi chạy)
echo "✍️  [3/4] Đang ký mã bundle (ad-hoc code sign)..."
codesign --force --deep --sign - "$APP_DIR"

# 5. Đóng gói thành file cài đặt macOS .pkg
echo "🎁 [4/4] Đang đóng gói installer $PKG_NAME..."
productbuild --component "$APP_DIR" /Applications --version "$VERSION" "$ROOT_DIR/$PKG_NAME"

echo "=========================================================="
echo "✅ HOÀN TẤT! File cài đặt đã được tạo tại:"
echo "👉 $ROOT_DIR/$PKG_NAME"
echo "=========================================================="
