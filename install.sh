#!/bin/bash
# Komari 1Panel 生产部署脚本
# 功能: 下载、验证、解压、备份、权限设置

set -euo pipefail

# ==================== 配置 ====================
readonly DOWNLOAD_URL="https://1panel.komari.wiki/deploy.zip"
readonly TARGET_DIR="/opt/1panel/resource/apps/local"
readonly BACKUP_DIR="/opt/1panel/resource/apps/backups"
readonly LOG_FILE="/var/log/komari_install.log"
readonly TEMP_DIR=$(mktemp -d)

# ==================== 日志函数 ====================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $*"
    rm -rf "$TEMP_DIR"
    exit 1
}

success_exit() {
    log "SUCCESS: $*"
    rm -rf "$TEMP_DIR"
    exit 0
}

# ==================== 主流程 ====================
main() {
    log "开始安装 Komari 到 1Panel"
    
    # 1. 权限检查
    [[ $EUID -eq 0 ]] || error_exit "需要 root 权限运行"
    
    # 2. 检查 1Panel 目录
    [[ -d "$TARGET_DIR" ]] || error_exit "1Panel 目录不存在: $TARGET_DIR"
    
    # 3. 备份旧版本
    if [[ -d "$TARGET_DIR/komari" ]]; then
        log "发现旧版本，创建备份..."
        mkdir -p "$BACKUP_DIR"
        tar -czf "$BACKUP_DIR/komari_$(date +%Y%m%d_%H%M%S).tar.gz" -C "$TARGET_DIR" komari
    fi
    
    # 4. 下载
    log "下载部署包..."
    if ! wget -q --timeout=30 --tries=3 -O "$TEMP_DIR/deploy.zip" "$DOWNLOAD_URL"; then
        error_exit "下载失败，请检查网络和 URL"
    fi
    
    # 5. 验证文件
    [[ -s "$TEMP_DIR/deploy.zip" ]] || error_exit "下载文件为空"
    
    # 6. 解压
    log "解压到 $TARGET_DIR..."
    unzip -o -q "$TEMP_DIR/deploy.zip" -d "$TARGET_DIR"
    
    # 7. 验证结构
    local required_files=(
        "komari/data.yml"
        "komari/logo.png"
        "komari/README.md"
        "komari/1.1.3/data.yml"
        "komari/1.1.3/docker-compose.yml"
    )
    
    for file in "${required_files[@]}"; do
        [[ -f "$TARGET_DIR/$file" ]] || error_exit "文件缺失: $file"
    done
    
    # 8. 设置权限
    chown -R 1panel:1panel "$TARGET_DIR/komari" 2>/dev/null || true
    chmod -R 755 "$TARGET_DIR/komari"
    
    # 9. 清理
    rm -rf "$TEMP_DIR"
    
    # 10. 成功提示
    cat << EOF | tee -a "$LOG_FILE"

================================
✓ Komari 安装成功！
================================

请按以下步骤完成安装：
1. 登录 1Panel 管理面板
2. 进入 应用商店
3. 点击 同步本地应用
4. 搜索 "komari" 或查看 "实用工具" 分类
5. 点击安装

应用路径: $TARGET_DIR/komari
日志文件: $LOG_FILE

EOF
    
    success_exit "Komari 已成功部署到 1Panel"
}

# ==================== 执行 ====================
trap 'error_exit "脚本异常终止"' ERR
main "$@"