#!/bin/bash
# Komari 1Panel 生产部署脚本 - 自动提权版本
# 使用方法: bash -c "$(curl -sSL https://1panel.komari.wiki/install.sh)"

set -euo pipefail

# ==================== 配置 ====================
readonly DOWNLOAD_URL="https://1panel.komari.wiki/komari.zip"
readonly TARGET_DIR="/opt/1panel/resource/apps/local"
readonly BACKUP_DIR="/opt/1panel/resource/apps/backups"
readonly TEMP_DIR=$(mktemp -d)

# ==================== 权限检查 ====================
# 如果不是root用户，提示用户使用sudo重新执行
if [[ $EUID -ne 0 ]]; then
    cat << 'EOF' >&2

需要root权限来执行添加操作。
请使用以下命令运行此脚本：

  sudo bash -c "$(curl -sSL https://1panel.komari.wiki/install.sh)"

或者先下载再执行：
  curl -sSL https://1panel.komari.wiki/install.sh -o install.sh
  sudo bash install.sh

EOF
    exit 1
fi

# ==================== 主逻辑 ====================
error_exit() {
    echo "ERROR: $*" >&2
    rm -rf "$TEMP_DIR"
    exit 1
}

success_exit() {
    echo "SUCCESS: $*"
    rm -rf "$TEMP_DIR"
    exit 0
}

main() {
    echo "开始添加 Komari 到 1Panel 应用商店"
    
    # 1. 检查 1Panel 目录
    [[ -d "$TARGET_DIR" ]] || error_exit "1Panel 目录不存在: $TARGET_DIR"
    
    # 2. 备份旧版本并检测现有容器
    local has_existing_container=false
    
    if [[ -d "$TARGET_DIR/komari" ]]; then
        echo "发现旧版本，创建备份..."
        mkdir -p "$BACKUP_DIR"
        tar -czf "$BACKUP_DIR/komari_$(date +%Y%m%d_%H%M%S).tar.gz" -C "$TARGET_DIR" komari
        
        # 检测是否有Docker容器同时包含komari和1panel
        if command -v docker &> /dev/null; then
            if docker ps -a --filter "name=komari" --filter "name=1panel" --format '{{.Names}}' | grep -q .; then
                has_existing_container=true
                echo "检测到已存在的 Komari Docker 容器"
            fi
        fi
    fi
    
    # 3. 下载
    echo "下载部署包..."
    if ! wget -q --timeout=30 --tries=3 -O "$TEMP_DIR/komari.zip" "$DOWNLOAD_URL"; then
        error_exit "下载失败，请检查网络和 URL"
    fi
    
    # 4. 验证文件
    [[ -s "$TEMP_DIR/komari.zip" ]] || error_exit "下载文件为空"
    
    # 5. 解压
    echo "解压到 $TARGET_DIR..."
    unzip -o -q "$TEMP_DIR/komari.zip" -d "$TARGET_DIR"
    
    # 6. 验证结构
    local required_files=(
        "komari/data.yml"
        "komari/logo.png"
        "komari/README.md"
        "komari/1.1.4/data.yml"
        "komari/1.1.4/docker-compose.yml"
    )
    
    for file in "${required_files[@]}"; do
        [[ -f "$TARGET_DIR/$file" ]] || error_exit "文件缺失: $file"
    done
    
    # 7. 设置权限
    chmod -R 755 "$TARGET_DIR/komari"
    
    # 8. 清理
    rm -rf "$TEMP_DIR"
    
    # 9. 成功提示（根据是否检测到现有容器显示不同指引）
    if [[ "$has_existing_container" == true ]]; then
        cat << EOF

================================
✓ Komari 在 1panel 应用商店更新成功！
================================

请按以下步骤完成更新：
1. 登录 1Panel 管理面板
2. 进入 应用商店
3. 点击 同步本地应用
4. 点击顶部 可升级
5. 找到 komari，点击升级即可

应用路径: $TARGET_DIR/komari

EOF
        success_exit "Komari 已成功更新到 1Panel 应用商店"
    else
        cat << EOF

================================
✓ Komari 添加至 1panel 应用商店成功！
================================

请按以下步骤完成安装：
1. 登录 1Panel 管理面板
2. 进入 应用商店
3. 点击 同步本地应用
4. 搜索 "komari" 或查看 "实用工具" 分类
5. 点击安装，可自行更改配置

应用路径: $TARGET_DIR/komari

EOF
        success_exit "Komari 已成功添加到 1Panel 应用商店"
    fi
}

trap 'error_exit "脚本异常终止"' ERR
main "$@"
