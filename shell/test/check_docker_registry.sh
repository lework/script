#!/bin/bash

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Docker registry 列表
REGISTRIES=(
    "https://docker-registry.nmqu.com"
    "https://docker.1ms.run"
    "https://docker.1panel.live"
    "https://docker.1panel.top"
    "https://docker.actima.top"
    "https://docker.aityp.com"
    "https://docker.hlmirror.com"
    "https://docker.kejilion.pro"
    "https://docker.m.daocloud.io"
    "https://docker.melikeme.cn"
    "https://docker.tbedu.top"
    "https://docker.xuanyuan.me"
    "https://dockercf.jsdelivr.fyi"
    "https://dockerhub.xisoul.cn"
    "https://dockerproxy.net"
    "https://dockerpull.pw"
    "https://doublezonline.cloud"
    "https://hub.fast360.xyz"
    "https://hub.rat.dev"
    "https://hub.xdark.top"
    "https://image.cloudlayer.icu"
    "https://lispy.org"
)

# 检测系统环境
detect_system() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        DAEMON_JSON_PATH="/etc/docker/daemon.json"
        DOCKER_SERVICE="docker"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        DAEMON_JSON_PATH="$HOME/.docker/daemon.json"
        DOCKER_SERVICE="docker"
    else
        # Windows WSL 或其他
        DAEMON_JSON_PATH="/etc/docker/daemon.json"
        DOCKER_SERVICE="docker"
    fi
    
    log_info "检测到系统类型: $OSTYPE"
    log_info "Docker daemon.json 路径: $DAEMON_JSON_PATH"
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    command -v curl >/dev/null 2>&1 || missing_deps+=("curl")
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    command -v docker >/dev/null 2>&1 || missing_deps+=("docker")
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "缺少依赖工具: ${missing_deps[*]}"
        log_info "请安装缺少的依赖:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        
        # 提供安装建议
        log_info "安装建议:"
        if command -v apt-get >/dev/null 2>&1; then
            echo "  sudo apt-get update && sudo apt-get install -y curl jq docker.io"
        elif command -v yum >/dev/null 2>&1; then
            echo "  sudo yum install -y curl jq docker"
        elif command -v brew >/dev/null 2>&1; then
            echo "  brew install curl jq docker"
        fi
        
        exit 1
    fi
}

# 检测registry可用性
check_registry() {
    local registry_url="$1"
    local timeout=10
    
    log_info "检测 registry: $registry_url"
    
    # 方法1: 检查v2 API端点
    if curl -s --connect-timeout $timeout --max-time $timeout "$registry_url/v2/" > /dev/null 2>&1; then
        log_success "✓ $registry_url 连接正常 (v2 API)"
        return 0
    fi
    
    # 方法2: 检查基本连接
    if curl -s --connect-timeout $timeout --max-time $timeout "$registry_url" > /dev/null 2>&1; then
        log_success "✓ $registry_url 基本连接可用"
        return 0
    fi
    
    # 方法3: 尝试HEAD请求
    if curl -I --connect-timeout $timeout --max-time $timeout "$registry_url" > /dev/null 2>&1; then
        log_success "✓ $registry_url HEAD请求成功"
        return 0
    fi
    
    log_warning "✗ $registry_url 连接失败"
    return 1
}

# 测试Docker pull性能
test_registry_performance() {
    local registry_url="$1"
    local test_image="debian:stable-slim"
    
    log_info "测试 $registry_url 的拉取性能..."
    
    # 创建临时配置
    local temp_daemon_config="/tmp/daemon_test_$$.json"
    cat > "$temp_daemon_config" << EOF
{
    "registry-mirrors": ["$registry_url"]
}
EOF
    
    # 测试拉取时间
    local start_time=$(date +%s)
    
    # 使用临时配置测试（仅作为参考，实际可能需要重启docker服务）
    if timeout 30 docker pull "$test_image" > /dev/null 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "✓ $registry_url 性能测试通过 (耗时: ${duration}s)"
        
        # 清理测试镜像
        docker rmi "$test_image" > /dev/null 2>&1 || true
        rm -f "$temp_daemon_config"
        return 0
    else
        log_warning "✗ $registry_url 性能测试失败"
        rm -f "$temp_daemon_config"
        return 1
    fi
}

# 备份现有配置
backup_daemon_json() {
    if [ -f "$DAEMON_JSON_PATH" ]; then
        local backup_path="${DAEMON_JSON_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$DAEMON_JSON_PATH" "$backup_path"
        log_success "已备份现有配置到: $backup_path"
    else
        log_info "未找到现有的 daemon.json 配置文件"
    fi
}

# 更新daemon.json配置
update_daemon_json() {
    local available_registries=("$@")
    
    if [ ${#available_registries[@]} -eq 0 ]; then
        log_error "没有可用的registry，跳过配置更新"
        return 1
    fi
    
    log_info "更新 daemon.json 配置..."
    
    # 确保目录存在
    mkdir -p "$(dirname "$DAEMON_JSON_PATH")"
    
    # 读取现有配置或创建新配置
    local config="{}"
    if [ -f "$DAEMON_JSON_PATH" ]; then
        config=$(cat "$DAEMON_JSON_PATH")
    fi
    
    # 构建registry mirrors数组
    local mirrors_json="["
    for i in "${!available_registries[@]}"; do
        if [ $i -gt 0 ]; then
            mirrors_json+=","
        fi
        mirrors_json+="\"${available_registries[$i]}\""
    done
    mirrors_json+="]"
    
    # 更新配置
    local new_config
    if command -v jq >/dev/null 2>&1; then
        new_config=$(echo "$config" | jq --argjson mirrors "$mirrors_json" '. + {"registry-mirrors": $mirrors}')
    else
        # 如果没有jq，使用简单的JSON构建
        new_config="{\"registry-mirrors\": $mirrors_json}"
        if [ "$config" != "{}" ]; then
            log_warning "没有找到jq工具，将覆盖现有配置"
        fi
    fi
    
    # 写入配置文件
    echo "$new_config" | jq '.' > "$DAEMON_JSON_PATH" 2>/dev/null || echo "$new_config" > "$DAEMON_JSON_PATH"
    
    log_success "已更新 daemon.json 配置"
    log_info "配置的镜像源:"
    for registry in "${available_registries[@]}"; do
        echo "  - $registry"
    done
    
    # 显示最终配置
    echo
    log_info "最终的daemon.json配置:"
    cat "$DAEMON_JSON_PATH"
}

# 重启Docker服务
restart_docker_service() {
    log_info "重启 Docker 服务..."
    
    # 检查是否有root权限
    if [ "$EUID" -ne 0 ]; then
        log_warning "需要root权限重启Docker服务"
        log_info "请手动执行以下命令:"
        echo "  sudo systemctl restart $DOCKER_SERVICE"
        echo "  # 或者"
        echo "  sudo service $DOCKER_SERVICE restart"
        echo "  # Windows Docker Desktop:"
        echo "  # 重启Docker Desktop应用程序"
        return 0
    fi
    
    # 尝试不同的重启方法
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart "$DOCKER_SERVICE"
        systemctl status "$DOCKER_SERVICE" --no-pager
    elif command -v service >/dev/null 2>&1; then
        service "$DOCKER_SERVICE" restart
        service "$DOCKER_SERVICE" status
    else
        log_warning "无法自动重启Docker服务，请手动重启"
        return 1
    fi
    
    log_success "Docker 服务重启完成"
}

# 验证配置
verify_configuration() {
    log_info "验证Docker配置..."
    
    if docker info > /dev/null 2>&1; then
        if docker info | grep -A 10 "Registry Mirrors:" > /dev/null 2>&1; then
            log_success "Docker镜像源配置验证成功"
            docker info | grep -A 10 "Registry Mirrors:"
        else
            log_warning "Docker运行正常，但未找到镜像源配置信息"
        fi
    else
        log_error "Docker服务未运行或配置有误"
        return 1
    fi
}

# 显示使用帮助
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -t, --test     仅测试registry连接性，不更新配置"
    echo "  -p, --perf     包含性能测试"
    echo "  -v, --verify   验证现有配置"
    echo ""
    echo "示例:"
    echo "  $0               # 检测并配置可用的registry"
    echo "  $0 --test        # 仅测试registry连接性"
    echo "  $0 --verify      # 验证现有Docker配置"
}

# 主函数
main() {
    local test_only=false
    local include_perf=false
    local verify_only=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -t|--test)
                test_only=true
                shift
                ;;
            -p|--perf)
                include_perf=true
                shift
                ;;
            -v|--verify)
                verify_only=true
                shift
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "========================================"
    echo "Docker Registry 检测和配置工具"
    echo "========================================"
    echo
    
    # 如果只是验证配置
    if [ "$verify_only" = true ]; then
        detect_system
        verify_configuration
        exit 0
    fi
    
    # 检测系统环境
    detect_system
    
    # 检查依赖
    check_dependencies
    
    # 检测可用的registry
    log_info "开始检测 Docker Registry 可用性..."
    available_registries=()
    
    for registry in "${REGISTRIES[@]}"; do
        if check_registry "$registry"; then
            available_registries+=("$registry")
        fi
    done
    
    echo
    log_info "检测结果汇总:"
    echo "可用的 Registry 数量: ${#available_registries[@]}/${#REGISTRIES[@]}"
    
    if [ ${#available_registries[@]} -eq 0 ]; then
        log_error "没有找到可用的 Docker Registry"
        log_info "请检查网络连接或稍后重试"
        exit 1
    fi
    
    # 如果只是测试模式
    if [ "$test_only" = true ]; then
        log_info "测试模式，不更新配置"
        exit 0
    fi
    
    # 性能测试
    if [ "$include_perf" = true ]; then
        echo
        log_info "开始性能测试..."
        tested_registries=()
        for registry in "${available_registries[@]}"; do
            if test_registry_performance "$registry"; then
                tested_registries+=("$registry")
            fi
        done
        available_registries=("${tested_registries[@]}")
        
        if [ ${#available_registries[@]} -eq 0 ]; then
            log_error "所有registry性能测试都失败"
            exit 1
        fi
    fi
    
    # 备份和更新配置
    echo
    log_info "准备更新 Docker 配置..."
    backup_daemon_json
    
    if update_daemon_json "${available_registries[@]}"; then
        echo
        log_success "配置更新完成"
        
        # 询问是否重启Docker
        echo
        read -p "是否重启 Docker 服务使配置生效? [Y/n]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            restart_docker_service
            sleep 3
            verify_configuration
        else
            log_info "请手动重启 Docker 服务使配置生效"
        fi
    fi
    
    echo
    log_success "脚本执行完成!"
}

# 错误处理
trap 'log_error "脚本执行被中断"; exit 1' INT TERM

# 执行主函数
main "$@"