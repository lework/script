#!/bin/bash
#
# Docker Image Manager Script
# Version: 1.0.0
# Description: 管理 Docker 镜像依赖关系和构建的工具脚本


# 颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 默认的 Dockerfile 目录
DOCKERFILE_DIR=${DOCKERFILE_DIR:-./}

# 全局变量
declare -A DOCKERFILE_FROM_CACHE
declare -A DOCKERFILE_IMAGE_CACHE

# 初始化缓存
init_cache() {
    while IFS= read -r dockerfile; do
        local dir=$(dirname "$dockerfile")
        local image_alias=$(echo "$dir" | sed "s|^${DOCKERFILE_DIR}||")
        local build_script="$dir/build.sh"

        DOCKERFILE_FROM_CACHE[$image_alias]=$(parse_from_image "$dockerfile" "$build_script" | sort)
        DOCKERFILE_IMAGE_CACHE[$image_alias]=$(get_image_paths "$build_script" | sort)
    done < <(find "$DOCKERFILE_DIR" -name "Dockerfile" -type f | sort)
}

# 获取镜像地址列表
get_image_paths() {
    local build_script=$1
    local images=()
    
    if [ -f "$build_script" ]; then
        # 先尝试从脚本执行结果获取
        local script_output
        script_output=$(bash "$build_script" list-tags 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$script_output" ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && images+=("$line")
            done <<< "$script_output"
            printf "%s\n" "${images[@]}"
            return
        fi
        
        # 回退到解析脚本内容
        if grep -q "^image_paths=" "$build_script"; then
            # 提取数组声明部分
            local array_content
            array_content=$(awk '/^image_paths=\(/{p=1;next} /^\)/{p=0} p{print}' "$build_script" | \
                          grep -E '".+"' | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//')
            while IFS= read -r line; do
                [ -n "$line" ] && images+=("$line")
            done <<< "$array_content"
        else
            # 尝试读取单个镜像声明
            while IFS= read -r line; do
                if [[ $line =~ ^[[:space:]]*image(_path)?=\" ]]; then
                    images+=($(echo "$line" | cut -d'=' -f2- | tr -d '"' | tr -d ' '))
                fi
            done < "$build_script"
        fi
    fi
    printf "%s\n" "${images[@]}"
}

# 获取所有镜像信息
get_images() {
    echo -e "${GREEN}所有镜像信息:${NC}\n"
    
    # 计算最长别名长度
    local max_alias_len=0
    
    for key in "${!DOCKERFILE_IMAGE_CACHE[@]}"; do
        local alias_len=$(echo $key| wc -c)
        if (( alias_len > max_alias_len )); then
            max_alias_len=$alias_len
        fi
    done
    
    # 设置列宽 (最长别名长度 + 4个空格的边距)
    local col_width=$((max_alias_len + 4))
    local padding=""
    printf -v padding "%-${col_width}s" " "
    
    echo -e "${YELLOW}别名$(printf "%-$((col_width-4))s" " ")镜像地址${NC}"
    echo "$(printf '%0.s-' $(seq 1 $((col_width + 50))))"
    
    local last_alias=""
    for key in "${!DOCKERFILE_IMAGE_CACHE[@]}"; do
        read -a images <<< ${DOCKERFILE_IMAGE_CACHE[$key]}

        # 显示镜像信息
        for i in "${!images[@]}"; do
            if [ "$key" != "$last_alias" ]; then
                printf "%-${col_width}s %s\n" "$key" "${images[$i]}"
                last_alias="$key"
            else
                printf "%s %s\n" "$padding" "${images[$i]}"
            fi
        done
    done
}

# 获取镜像依赖关系
get_dependencies() {
    local image_alias=$1
    
    if [ -z "$image_alias" ]; then
        echo -e "${RED}请指定镜像别名${NC}"
        exit 1
    fi
    
    # 查找对应的Dockerfile
    dockerfile="$DOCKERFILE_DIR/$image_alias/Dockerfile"
    if [ ! -f "$dockerfile" ]; then
        echo -e "${RED}找不到 $dockerfile${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}镜像 $image_alias 的依赖关系:${NC}\n"
    
    # 获取FROM依赖
    echo -e "${YELLOW}依赖的镜像:${NC}"
    echo "${DOCKERFILE_FROM_CACHE[$image_alias]}" | tr ' ' '\n'
    echo
    
    # 显示当前镜像的标签
    echo -e "${YELLOW}编译后的标签列表:${NC}"

    for image in ${DOCKERFILE_IMAGE_CACHE[$image_alias]}; do
        echo "  └─ $image"
    done
    echo
    
    # 查找被哪些镜像依赖
    echo -e "${YELLOW}被以下镜像依赖:${NC}"
    local dependents=()

    for source_image in ${DOCKERFILE_IMAGE_CACHE[$image_alias]}; do
        for key in "${!DOCKERFILE_FROM_CACHE[@]}"; do
                for from_image in "${DOCKERFILE_FROM_CACHE[$key]}"; do
                    if check_image_dependency "$from_image" "$source_image"; then
                        dependents+=("$key")
                    fi
                done
        done
    done 
    
    # 输出去重后的依赖列表
    printf "%s\n" "${dependents[@]}" | sort -u
}

# 构建依赖镜像
build_dependents() {
    local image_alias=$1
    
    if [ -z "$image_alias" ]; then
        echo -e "${RED}请指定镜像别名${NC}"
        exit 1
    fi
    
    # 获取所有依赖此镜像的其他镜像
    local dependents=()
    for source_image in ${DOCKERFILE_IMAGE_CACHE[$image_alias]}; do
      for key in "${!DOCKERFILE_FROM_CACHE[@]}"; do
           for from_image in "${DOCKERFILE_FROM_CACHE[$key]}"; do
               if check_image_dependency "$from_image" "$source_image"; then
                   dependents+=("$key")
		   break
               fi
           done
       done
    done
    
    # 去重依赖列表
    readarray -t dependents < <(printf '%s\n' "${dependents[@]}" | sort -u)
    
    if [ ${#dependents[@]} -eq 0 ]; then
        echo -e "${YELLOW}没有找到依赖 $image_alias 的镜像${NC}"
        exit 0
    fi

    echo -e "${GREEN}开始构建依赖 $image_alias 的镜像:${NC}\n"

    # 构建每个依赖镜像
    for dependent in "${dependents[@]}"; do
        echo -e "${YELLOW}构建 $dependent ${NC}"
        if [ -f "$DOCKERFILE_DIR/$dependent/build.sh" ]; then
            (cd "$DOCKERFILE_DIR/$dependent" && bash build.sh)
        else
            echo -e "${RED}找不到构建脚本 $DOCKERFILE_DIR/$dependent/build.sh${NC}"
        fi
    done
}

# 解析Dockerfile中的FROM指令
parse_from_image() {
    local dockerfile=$1
    local build_script=$2
    local from_images=()
    
    # 读取FROM指令
    while IFS= read -r line; do
        if [[ $line =~ ^FROM[[:space:]]+(.+)$ ]]; then
            local from_image="${BASH_REMATCH[1]}"
            # 处理多阶段构建的命名
            from_image="${from_image%% as *}"
            from_image="${from_image%% AS *}"
            
            # 处理变量替换
            if [[ $from_image =~ \$\{.+\} ]] && [ -f "$build_script" ]; then
                # 获取build.sh中的所有变量
                while IFS= read -r build_line; do
                    if [[ $build_line =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
                        local var_name="${BASH_REMATCH[1]}"
                        local var_value="${BASH_REMATCH[2]//\"/}"
                        from_image=${from_image//\$\{$var_name\}/$var_value}
                    fi
                done < "$build_script"
            fi
            from_images+=("$from_image")
        fi
    done < "$dockerfile"
    
    printf "%s\n" "${from_images[@]}"
}

# 检查镜像依赖关系
check_image_dependency() {
    local from_image="$1"
    shift
    local target_images=("$@")
    
    # 标准化镜像名称（移除标签）
    local from_base="${from_image%:*}"
    from_base="${from_base#harbor.*/}"  # 移除仓库前缀
    
    for target in "${target_images[@]}"; do
        local target_base="${target%:*}"
        target_base="${target_base#harbor.*/}"  # 移除仓库前缀
        
        if [[ "$from_base" == "$target_base" ]]; then
            return 0
        fi
    done
    return 1
}

# 递归生成依赖树
generate_dependency_tree() {
    local image_alias=$1
    local prefix=$2
    local last=$3
    local visited=($4)

    # 检查是否已访问过该节点（防止循环依赖）
    for v in "${visited[@]}"; do
        if [[ "$v" == "$image_alias" ]]; then
            if [ "$last" == "true" ]; then
                echo -e "${prefix}└── ${YELLOW}$image_alias${NC} (循环依赖)"
            else
                echo -e "${prefix}├── ${YELLOW}$image_alias${NC} (循环依赖)"
            fi
            return
        fi
    done
    
    # 获取镜像地址
    local dockerfile="$DOCKERFILE_DIR/$image_alias/Dockerfile"
    if [ ! -f "$dockerfile" ]; then
        if (("$last" == "true")); then
            echo -e "${prefix}└── ${RED}$image_alias (未找到 Dockerfile)${NC}"
        else
            echo -e "${prefix}├── ${RED}$image_alias (未找到 Dockerfile)${NC}"
        fi
        return
    fi

    # 显示当前节点
    if [ "$last" == "true" ]; then
        echo -e "${prefix}└── ${GREEN}$image_alias${NC}"
        prefix="${prefix}    "
    else
        echo -e "${prefix}├── ${GREEN}$image_alias${NC}"
        prefix="${prefix}│   "
    fi
    
    # 将当前节点添加到已访问列表
    visited+=($image_alias)
    
    # 获取所有依赖此镜像的其他镜像
    local dependents=()
    for source_image in ${DOCKERFILE_IMAGE_CACHE[$image_alias]}; do
       for key in "${!DOCKERFILE_FROM_CACHE[@]}"; do
           for from_image in "${DOCKERFILE_FROM_CACHE[$key]}"; do
               if check_image_dependency "$from_image" "$source_image"; then
                   dependents+=("$key")
                   break
               fi
           done
       done
    done
    
    # 去重依赖列表
    dependents=($(printf "%s\n" "${dependents[@]}" | sort -u))
    
    local last_idx=$((${#dependents[@]} - 1))
    local i=0
    for dependent in "${dependents[@]}"; do
        if [ $i -eq $last_idx ]; then
            generate_dependency_tree "$dependent" "$prefix" "true" "${visited[*]}"
        else
            generate_dependency_tree "$dependent" "$prefix" "false" "${visited[*]}"
        fi
        ((i++))
    done
}

# 获取所有基础镜像(没有被其他镜像依赖的镜像)
get_base_images() {
    local dependent_images=()
    
    # 获取所有依赖关系
    for img in "${!DOCKERFILE_IMAGE_CACHE[@]}"; do
        for source_image in ${DOCKERFILE_IMAGE_CACHE[$img]}; do
           for key in "${!DOCKERFILE_FROM_CACHE[@]}"; do
               for from_image in "${DOCKERFILE_FROM_CACHE[$key]}"; do
                   if check_image_dependency "$from_image" "$source_image"; then
                       dependent_images+=("$key")
                       break
                   fi
               done
           done
        done
    done
    
    # 找出没有被依赖的镜像
    for img in "${!DOCKERFILE_IMAGE_CACHE[@]}"; do
        local is_dependent=0
        for dep in "${dependent_images[@]}"; do
            if [ "$img" == "$dep" ]; then
                is_dependent=1
                break
            fi
        done
        if [ $is_dependent -eq 0 ]; then
            echo "$img"
        fi
    done | sort -u
}

# 显示依赖树
show_dependency_tree() {
    local image_alias=$1
    
    if [ -z "$image_alias" ]; then
        echo -e "${GREEN}所有镜像依赖树:${NC}\n"
        # 获取所有基础镜像
        local base_images=($(get_base_images))
        local last_idx=$((${#base_images[@]} - 1))
        local i=0
        
        # 显示每个基础镜像的依赖树
        for base_image in "${base_images[@]}"; do
            if [ $i -eq $last_idx ]; then
                generate_dependency_tree "$base_image" "" "true" ""
            else
                generate_dependency_tree "$base_image" "" "false" ""
            fi
            ((i++))
            # 如果不是最后一个基础镜像，添加空行
            if [ $i -ne ${#base_images[@]} ]; then
                echo "│"
            fi
        done
    else
        echo -e "${GREEN}镜像 $image_alias 依赖树:${NC}\n"
        generate_dependency_tree "$image_alias" "" "true" ""
    fi
}

init_cache

# 命令行参数处理
case "$1" in
    "list")
        get_images
        ;;
    "deps")
        get_dependencies "$2"
        ;;
    "build")
        build_dependents "$2"
        ;;
    "tree")
        show_dependency_tree "$2"
        ;;
    *)
        echo -e "用法:\n"
        echo -e "  $0 list                     # 列出所有镜像"
        echo -e "  $0 deps <image-alias>       # 显示指定镜像的依赖关系"
        echo -e "  $0 build <image-alias>      # 构建依赖指定镜像的所有镜像"
        echo -e "  $0 tree [image-alias]       # 以树形结构显示镜像依赖关系(不指定则显示所有)"
        exit 1
        ;;
esac

exit 0
[root@k8s-master-node1 scripts]# vim image_manager.sh_1
[root@k8s-master-node1 scripts]# bash image_manager.sh_1 list
所有镜像信息:

别名                       镜像地址
-----------------------------------------------------------------------------
common/tools/node           harbor.lework.cn/common/tools/node:20
                            harbor.lework.cn/common/tools/node:20.17
                            harbor.lework.cn/common/tools/node:20.17.0
                            harbor.lework.cn/common/tools/node:20.17.0-debian11
                            harbor.lework.cn/common/tools/node:20.17-debian11
                            harbor.lework.cn/common/tools/node:20-debian11

common/tools/php            harbor.lework.cn/common/tools/php:7
                            harbor.lework.cn/common/tools/php:7.2
                            harbor.lework.cn/common/tools/php:7.2-debian11
                            harbor.lework.cn/common/tools/php:7-debian11

common/runtime/php          harbor.lework.cn/common/runtime/php:7
                            harbor.lework.cn/common/runtime/php:7.2
                            harbor.lework.cn/common/runtime/php:7.2-debian11
                            harbor.lework.cn/common/runtime/php:7-debian11

common/os/debian            harbor.lework.cn/common/os/debian:bullseye
                            harbor.lework.cn/common/os/debian:bullseye-20240926-slim
                            harbor.lework.cn/common/os/debian:bullseye-slim

common/runtime/node         harbor.lework.cn/common/runtime/node:20
                            harbor.lework.cn/common/runtime/node:20.17
                            harbor.lework.cn/common/runtime/node:20.17.0
                            harbor.lework.cn/common/runtime/node:20.17.0-debian11
                            harbor.lework.cn/common/runtime/node:20.17-debian11
                            harbor.lework.cn/common/runtime/node:20-debian11

common/runtime/python       harbor.lework.cn/common/runtime/python:3
                            harbor.lework.cn/common/runtime/python:3.11
                            harbor.lework.cn/common/runtime/python:3.11.10
                            harbor.lework.cn/common/runtime/python:3.11.10-debian11
                            harbor.lework.cn/common/runtime/python:3.11-debian11
                            harbor.lework.cn/common/runtime/python:3-debian11

common/runtime/openjdk      harbor.lework.cn/common/runtime/openjdk:24-debian11

common/tools/openjdk        harbor.lework.cn/common/tools/openjdk:24
                            harbor.lework.cn/common/tools/openjdk:24-debian11
                            harbor.lework.cn/common/tools/openjdk:24-ea+30
                            harbor.lework.cn/common/tools/openjdk:24-ea+30-debian11

common/runtime/nginx        harbor.lework.cn/common/runtime/nginx:debian11

common/tools/dind           harbor.lework.cn/common/tools/dind:latest

common/tools/python         harbor.lework.cn/common/tools/python:3
                            harbor.lework.cn/common/tools/python:3.11
                            harbor.lework.cn/common/tools/python:3.11.10
                            harbor.lework.cn/common/tools/python:3.11.10-debian11
                            harbor.lework.cn/common/tools/python:3.11-debian11
                            harbor.lework.cn/common/tools/python:3-debian11

common/tools/ansible        harbor.leops.local/common/tools/ansible:7
                            harbor.leops.local/common/tools/ansible:7.6
                            harbor.leops.local/common/tools/ansible:7.6.0

common/runtime/go           harbor.lework.cn/common/runtime/golang:debian11

common/tools/maven          harbor.lework.cn/common/tools/maven:3
                            harbor.lework.cn/common/tools/maven:3.9
                            harbor.lework.cn/common/tools/maven:3.9.9
                            harbor.lework.cn/common/tools/maven:3.9.9-debian11
                            harbor.lework.cn/common/tools/maven:3.9-debian11
                            harbor.lework.cn/common/tools/maven:3-debian11

common/tools/go             harbor.lework.cn/common/tools/golang:1.23
                            harbor.lework.cn/common/tools/golang:1.23.3
                            harbor.lework.cn/common/tools/golang:1.23.3-debian11
                            harbor.lework.cn/common/tools/golang:1.23-debian11

[root@k8s-master-node1 scripts]# bash image_manager.sh_1 tree
所有镜像依赖树:

image_manager.sh_1: line 282: visited[@]: unbound variable
[root@k8s-master-node1 scripts]# vim image_manager.sh_1
[root@k8s-master-node1 scripts]# vim image_manager.sh_1
[root@k8s-master-node1 scripts]# vim image_manager.sh_1
[root@k8s-master-node1 scripts]# vim image_manager.sh_1
[root@k8s-master-node1 scripts]# bash image_manager.sh_1 tree
所有镜像依赖树:

├── app-build/go
image_manager.sh_1: line 337: dependents[@]: unbound variable
[root@k8s-master-node1 scripts]#  cat image_manager.sh
image_manager.sh       image_manager.sh_1     image_manager.sh_2     image_manager.sh_3.sh  
[root@k8s-master-node1 scripts]#  cat image_manager.sh
#!/bin/bash

# 颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 默认的 Dockerfile 目录
DOCKERFILE_DIR=${DOCKERFILE_DIR:-../}

# 全局变量
declare -A DOCKERFILE_FROM_CACHE
declare -A DOCKERFILE_IMAGE_CACHE

# 初始化缓存
init_cache() {
    while IFS= read -r dockerfile; do
        local dir=$(dirname "$dockerfile")
        local image_alias=$(echo "$dir" | sed "s|^${DOCKERFILE_DIR}||")
        local build_script="$dir/build.sh"

        DOCKERFILE_FROM_CACHE[$image_alias]=$(parse_from_image "$dockerfile" "$build_script" | sort)
        DOCKERFILE_IMAGE_CACHE[$image_alias]=$(get_image_paths "$build_script" | sort)
    done < <(find "$DOCKERFILE_DIR" -name "Dockerfile" -type f | sort)
}

# 获取镜像地址列表
get_image_paths() {
    local build_script=$1
    local images=()
    
    if [ -f "$build_script" ]; then
        # 先尝试从脚本执行结果获取
        local script_output
        script_output=$(bash "$build_script" list-tags 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$script_output" ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && images+=("$line")
            done <<< "$script_output"
            printf "%s\n" "${images[@]}"
            return
        fi
        
        # 回退到解析脚本内容
        if grep -q "^image_paths=" "$build_script"; then
            # 提取数组声明部分
            local array_content
            array_content=$(awk '/^image_paths=\(/{p=1;next} /^\)/{p=0} p{print}' "$build_script" | \
                          grep -E '".+"' | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//')
            while IFS= read -r line; do
                [ -n "$line" ] && images+=("$line")
            done <<< "$array_content"
        else
            # 尝试读取单个镜像声明
            while IFS= read -r line; do
                if [[ $line =~ ^[[:space:]]*image(_path)?=\" ]]; then
                    images+=($(echo "$line" | cut -d'=' -f2- | tr -d '"' | tr -d ' '))
                fi
            done < "$build_script"
        fi
    fi
    printf "%s\n" "${images[@]}"
}

# 获取所有镜像信息
get_images() {
    echo -e "${GREEN}所有镜像信息:${NC}\n"
    
    # 计算最长别名长度
    local max_alias_len=0
    
    for key in "${!DOCKERFILE_IMAGE_CACHE[@]}"; do
        local alias_len=$(echo $key| wc -c)
        if (( alias_len > max_alias_len )); then
            max_alias_len=$alias_len
        fi
    done
    
    # 设置列宽 (最长别名长度 + 4个空格的边距)
    local col_width=$((max_alias_len + 4))
    local padding=""
    printf -v padding "%-${col_width}s" " "
    
    echo -e "${YELLOW}别名$(printf "%-$((col_width-4))s" " ")镜像地址${NC}"
    echo "$(printf '%0.s-' $(seq 1 $((col_width + 50))))"
    
    local last_alias=""
    for key in "${!DOCKERFILE_IMAGE_CACHE[@]}"; do
        read -a images <<< ${DOCKERFILE_IMAGE_CACHE[$key]}

        # 显示镜像信息
        for i in "${!images[@]}"; do
            if [ "$key" != "$last_alias" ]; then
                printf "%-${col_width}s %s\n" "$key" "${images[$i]}"
                last_alias="$key"
            else
                printf "%s %s\n" "$padding" "${images[$i]}"
            fi
        done
    done
}

# 获取镜像依赖关系
get_dependencies() {
    local image_alias=$1
    
    if [ -z "$image_alias" ]; then
        echo -e "${RED}请指定镜像别名${NC}"
        exit 1
    fi
    
    # 查找对应的Dockerfile
    dockerfile="$DOCKERFILE_DIR/$image_alias/Dockerfile"
    if [ ! -f "$dockerfile" ]; then
        echo -e "${RED}找不到 $dockerfile${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}镜像 $image_alias 的依赖关系:${NC}\n"
    
    # 获取FROM依赖
    echo -e "${YELLOW}依赖的镜像:${NC}"
    echo "${DOCKERFILE_FROM_CACHE[$image_alias]}" | tr ' ' '\n'
    echo
    
    # 显示当前镜像的标签
    echo -e "${YELLOW}编译后的标签列表:${NC}"

    for image in ${DOCKERFILE_IMAGE_CACHE[$image_alias]}; do
        echo "  └─ $image"
    done
    echo
    
    # 查找被哪些镜像依赖
    echo -e "${YELLOW}被以下镜像依赖:${NC}"
    local dependents=()

    for source_image in ${DOCKERFILE_IMAGE_CACHE[$image_alias]}; do
        for key in "${!DOCKERFILE_FROM_CACHE[@]}"; do
                for from_image in "${DOCKERFILE_FROM_CACHE[$key]}"; do
                    if check_image_dependency "$from_image" "$source_image"; then
                        dependents+=("$key")
                    fi
                done
        done
    done 
    
    # 输出去重后的依赖列表
    printf "%s\n" "${dependents[@]}" | sort -u
}

# 构建依赖镜像
build_dependents() {
    local image_alias=$1
    
    if [ -z "$image_alias" ]; then
        echo -e "${RED}请指定镜像别名${NC}"
        exit 1
    fi
    
    # 获取所有依赖此镜像的其他镜像
    local dependents=()
    for source_image in ${DOCKERFILE_IMAGE_CACHE[$image_alias]}; do
      for key in "${!DOCKERFILE_FROM_CACHE[@]}"; do
           for from_image in "${DOCKERFILE_FROM_CACHE[$key]}"; do
               if check_image_dependency "$from_image" "$source_image"; then
                   dependents+=("$key")
                   break 2  # 找到一个匹配就跳出两层循环
               fi
           done
       done
    done
    
    # 去重依赖列表
    readarray -t dependents < <(printf '%s\n' "${dependents[@]}" | sort -u)
    
    if [ ${#dependents[@]} -eq 0 ]; then
        echo -e "${YELLOW}没有找到依赖 $image_alias 的镜像${NC}"
        exit 0
    fi

    echo -e "${GREEN}开始构建依赖 $image_alias 的镜像:${NC}\n"
    
    # 构建每个依赖镜像
    for dependent in "${dependents[@]}"; do
        echo -e "${YELLOW}构建 $dependent ${NC}"
        if [ -f "$DOCKERFILE_DIR/$dependent/build.sh" ]; then
            (cd "$DOCKERFILE_DIR/$dependent" && bash build.sh)
        else
            echo -e "${RED}找不到构建脚本 $DOCKERFILE_DIR/$dependent/build.sh${NC}"
        fi
    done
}

# 解析Dockerfile中的FROM指令
parse_from_image() {
    local dockerfile=$1
    local build_script=$2
    local from_images=()
    
    # 读取FROM指令
    while IFS= read -r line; do
        if [[ $line =~ ^FROM[[:space:]]+(.+)$ ]]; then
            local from_image="${BASH_REMATCH[1]}"
            # 处理多阶段构建的命名
            from_image="${from_image%% as *}"
            from_image="${from_image%% AS *}"
            
            # 处理变量替换
            if [[ $from_image =~ \$\{.+\} ]] && [ -f "$build_script" ]; then
                # 获取build.sh中的所有变量
                while IFS= read -r build_line; do
                    if [[ $build_line =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
                        local var_name="${BASH_REMATCH[1]}"
                        local var_value="${BASH_REMATCH[2]//\"/}"
                        from_image=${from_image//\$\{$var_name\}/$var_value}
                    fi
                done < "$build_script"
            fi
            from_images+=("$from_image")
        fi
    done < "$dockerfile"
    
    printf "%s\n" "${from_images[@]}"
}

# 检查镜像依赖关系
check_image_dependency() {
    local from_image="$1"
    shift
    local target_images=("$@")
    
    # 标准化镜像名称（移除标签）
    local from_base="${from_image%:*}"
    from_base="${from_base#harbor.*/}"  # 移除仓库前缀
    
    for target in "${target_images[@]}"; do
        local target_base="${target%:*}"
        target_base="${target_base#harbor.*/}"  # 移除仓库前缀
        
        if [[ "$from_base" == "$target_base" ]]; then
            return 0
        fi
    done
    return 1
}

# 递归生成依赖树
generate_dependency_tree() {
    local image_alias=$1
    local prefix=$2
    local last=$3
    local visited=($4)

    # 检查是否已访问过该节点（防止循环依赖）
    for v in "${visited[@]}"; do
        if [[ "$v" == "$image_alias" ]]; then
            if [ "$last" == "true" ]; then
                echo -e "${prefix}└── ${YELLOW}$image_alias${NC} (循环依赖)"
            else
                echo -e "${prefix}├── ${YELLOW}$image_alias${NC} (循环依赖)"
            fi
            return
        fi
    done
    
    # 获取镜像地址
    local dockerfile="$DOCKERFILE_DIR/$image_alias/Dockerfile"
    if [ ! -f "$dockerfile" ]; then
        if (("$last" == "true")); then
            echo -e "${prefix}└── ${RED}$image_alias (未找到 Dockerfile)${NC}"
        else
            echo -e "${prefix}├── ${RED}$image_alias (未找到 Dockerfile)${NC}"
        fi
        return
    fi

    # 显示当前节点
    if [ "$last" == "true" ]; then
        echo -e "${prefix}└── ${GREEN}$image_alias${NC}"
        prefix="${prefix}    "
    else
        echo -e "${prefix}├── ${GREEN}$image_alias${NC}"
        prefix="${prefix}│   "
    fi
    
    # 将当前节点添加到已访问列表
    visited+=($image_alias)
    
    # 获取所有依赖此镜像的其他镜像
    local dependents=()
    for source_image in ${DOCKERFILE_IMAGE_CACHE[$image_alias]}; do
       for key in "${!DOCKERFILE_FROM_CACHE[@]}"; do
           for from_image in "${DOCKERFILE_FROM_CACHE[$key]}"; do
               if check_image_dependency "$from_image" "$source_image"; then
                   dependents+=("$key")
                   break
               fi
           done
       done
    done
    
    # 去重依赖列表
    dependents=($(printf "%s\n" "${dependents[@]}" | sort -u))
    
    local last_idx=$((${#dependents[@]} - 1))
    local i=0
    for dependent in "${dependents[@]}"; do
        if [ $i -eq $last_idx ]; then
            generate_dependency_tree "$dependent" "$prefix" "true" "${visited[*]}"
        else
            generate_dependency_tree "$dependent" "$prefix" "false" "${visited[*]}"
        fi
        ((i++))
    done
}

# 获取所有基础镜像(没有被其他镜像依赖的镜像)
get_base_images() {
    local dependent_images=()
    
    # 获取所有依赖关系
    for img in "${!DOCKERFILE_IMAGE_CACHE[@]}"; do
        for source_image in ${DOCKERFILE_IMAGE_CACHE[$img]}; do
           for key in "${!DOCKERFILE_FROM_CACHE[@]}"; do
               for from_image in "${DOCKERFILE_FROM_CACHE[$key]}"; do
                   if check_image_dependency "$from_image" "$source_image"; then
                       dependent_images+=("$key")
                       break
                   fi
               done
           done
        done
    done
    
    # 找出没有被依赖的镜像
    for img in "${!DOCKERFILE_IMAGE_CACHE[@]}"; do
        local is_dependent=0
        for dep in "${dependent_images[@]}"; do
            if [ "$img" == "$dep" ]; then
                is_dependent=1
                break
            fi
        done
        if [ $is_dependent -eq 0 ]; then
            echo "$img"
        fi
    done | sort -u
}

# 显示依赖树
show_dependency_tree() {
    local image_alias=$1
    
    if [ -z "$image_alias" ]; then
        echo -e "${GREEN}所有镜像依赖树:${NC}\n"
        # 获取所有基础镜像
        local base_images=($(get_base_images))
        local last_idx=$((${#base_images[@]} - 1))
        local i=0
        
        # 显示每个基础镜像的依赖树
        for base_image in "${base_images[@]}"; do
            if [ $i -eq $last_idx ]; then
                generate_dependency_tree "$base_image" "" "true" ""
            else
                generate_dependency_tree "$base_image" "" "false" ""
            fi
            ((i++))
            # 如果不是最后一个基础镜像，添加空行
            if [ $i -ne ${#base_images[@]} ]; then
                echo "│"
            fi
        done
    else
        echo -e "${GREEN}镜像 $image_alias 依赖树:${NC}\n"
        generate_dependency_tree "$image_alias" "" "true" ""
    fi
}

init_cache

# 命令行参数处理
case "$1" in
    "list")
        get_images
        ;;
    "deps")
        get_dependencies "$2"
        ;;
    "build")
        build_dependents "$2"
        ;;
    "tree")
        show_dependency_tree "$2"
        ;;
    *)
        echo -e "用法:\n"
        echo -e "  $0 list                     # 列出所有镜像"
        echo -e "  $0 deps <image-alias>       # 显示指定镜像的依赖关系"
        echo -e "  $0 build <image-alias>      # 构建依赖指定镜像的所有镜像"
        echo -e "  $0 tree [image-alias]       # 以树形结构显示镜像依赖关系(不指定则显示所有)"
        exit 1
        ;;
esac

exit 0
