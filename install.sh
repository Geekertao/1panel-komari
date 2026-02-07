#!/bin/bash
# Komari 1Panel 生产部署脚本 - 自动提权版本
# 使用方法: bash -c "$(curl -sSL https://1panel.komari.wiki/install.sh)"

set -euo pipefail

# ==================== 配置 ====================
readonly DOWNLOAD_URL="https://1panel.komari.wiki/komari.zip"
readonly DOWNLOAD_URL_BACKUP="https://1p.komari.wiki/komari.zip"
readonly INSTALL_URL="https://1panel.komari.wiki/install.sh"
readonly INSTALL_URL_BACKUP="https://1p.komari.wiki/install.sh"
readonly TARGET_DIR="/opt/1panel/resource/apps/local"
readonly BACKUP_DIR="/opt/1panel/resource/apps/backups"
readonly TEMP_DIR=$(mktemp -d)
readonly CMD_NAME="1panel-komari"
readonly CMD_PATH="/usr/local/bin/${CMD_NAME}"

# ==================== 权限检查 ====================
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

# ==================== 安装快捷命令封装器 ====================
install_wrapper() {
    # 如果已经存在且内容相同，跳过
    if [[ -f "$CMD_PATH" ]]; then
        return 0
    fi
    
    echo "首次运行，正在安装快捷命令 ${CMD_NAME}..."
    
    # 注意：这里使用双引号heredoc以便插入变量，但需转义$
    cat > "$CMD_PATH" << EOF
#!/bin/bash
# 1Panel-Komari 快捷命令封装器
# 每次运行自动拉取最新脚本

set -euo pipefail

readonly SCRIPT_URL="${INSTALL_URL}"
readonly SCRIPT_URL_BACKUP="${INSTALL_URL_BACKUP}"

# 自动提权：如果不是root，使用sudo重新执行
if [[ \$EUID -ne 0 ]]; then
    exec sudo "\$0" "\$@"
fi

# 先尝试主地址，失败则尝试备用
if ! curl -sSL "\${SCRIPT_URL}" | bash -s -- "\$@"; then
    echo "主地址拉取失败，尝试备用地址..." >&2
    if ! curl -sSL "\${SCRIPT_URL_BACKUP}" | bash -s -- "\$@"; then
        echo "ERROR: 主备地址均不可用，请检查网络" >&2
        exit 1
    fi
fi
EOF

    chmod +x "$CMD_PATH"
    
    cat << EOF

================================
✓ 快捷命令已安装: ${CMD_NAME}
================================

以后你可以直接使用以下命令运行：

  ${CMD_NAME}              # 自动拉取并执行最新脚本
  sudo ${CMD_NAME}         # 显式使用管理员权限

EOF
    
    # 如果当前是通过curl管道执行的，提示用户下次使用方式
    if [[ ! -t 0 ]]; then
        cat << 'EOF'
提示：由于你是通过管道执行(curl | bash)，本次仍会继续执行安装。
下次请直接使用上面的命令。

按回车键继续，或按 Ctrl+C 退出...
EOF
        read -r
    fi
}

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
    # 安装快捷命令（首次运行）
    install_wrapper
    
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
    
    # 3. 下载（主备切换）
    echo "下载部署包..."
    if ! wget -q --timeout=30 --tries=3 -O "$TEMP_DIR/komari.zip" "$DOWNLOAD_URL"; then
        echo "主地址下载失败，尝试备用地址..."
        if ! wget -q --timeout=30 --tries=3 -O "$TEMP_DIR/komari.zip" "$DOWNLOAD_URL_BACKUP"; then
            error_exit "下载失败，主备地址均不可用，请检查网络"
        fi
        echo "备用地址下载成功"
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
        "komari/1.1.5/data.yml"
        "komari/1.1.5/docker-compose.yml"
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

提示：以后更新可直接运行 ${CMD_NAME} 命令

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

提示：以后更新可直接运行 ${CMD_NAME} 命令

EOF
        success_exit "Komari 已成功添加到 1Panel 应用商店"
    fi
}

trap 'error_exit "脚本异常终止"' ERR
main "$@"
