#!/bin/bash
# Build script for ddns-dynv6

set -e

# 切换到脚本所在目录
cd "$(dirname "$0")"

BUILD_DIR="$(pwd)/build"

echo "Working directory: $(pwd)"

# 清理（dh_clean 会删除 build/ 目录）
rm -rf "$BUILD_DIR"
dh_clean 2>/dev/null || true

# 构建
echo ""
echo "Building package..."
dpkg-buildpackage -us -uc -b

# 切回脚本目录
cd "$(dirname "$0")"

# 获取版本号
VERSION=$(dpkg-parsechangelog --show-field Version | head -1)
PACKAGE="ddns-dynv6"

echo ""
echo "Moving files to build directory..."
echo "Version: $VERSION"

# 检查并创建 build 目录
if [[ ! -d "$BUILD_DIR" ]]; then
    mkdir -p "$BUILD_DIR"
    echo "Created build directory: $BUILD_DIR"
fi

# 移动文件
mv "$(pwd)/../${PACKAGE}_${VERSION}_all.deb" "$BUILD_DIR/" 2>/dev/null || echo "No .deb file found"
mv "$(pwd)/../${PACKAGE}_${VERSION}_amd64.changes" "$BUILD_DIR/" 2>/dev/null || echo "No .changes file found"
mv "$(pwd)/../${PACKAGE}_${VERSION}_amd64.buildinfo" "$BUILD_DIR/" 2>/dev/null || echo "No .buildinfo file found"

echo ""
echo "=== Build complete ==="
ls -la "$BUILD_DIR"

echo ""
echo "Install: sudo dpkg -i $BUILD_DIR/${PACKAGE}_${VERSION}_all.deb"