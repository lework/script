#!/bin/bash

# 设置ES索引副本数量脚本
# 功能：将副本数不为1的索引批量设置为1
# 新增功能：查找有 index.store.type 配置的索引

# ES服务地址和认证信息，根据实际情况修改
ES_HOST="http://localhost:9200"
ES_USER=""
ES_PASS=""
AUTH_PARAM=""

if [ -n "$ES_USER" ] && [ -n "$ES_PASS" ]; then
    AUTH_PARAM="-u $ES_USER:$ES_PASS"
fi

# 验证jq命令是否安装
if ! command -v jq &> /dev/null; then
    echo "错误: 此脚本需要jq工具，请先安装jq"
    echo "可以使用以下命令安装:"
    echo "  - Ubuntu/Debian: sudo apt-get install jq"
    echo "  - CentOS/RHEL: sudo yum install jq"
    echo "  - MacOS: brew install jq"
    exit 1
fi

# 查找有 index.store.type 配置的索引
echo "正在查找有 index.store.type 配置的索引..."
echo "========================================"

# 获取所有索引列表
indices=$(curl -s $AUTH_PARAM "$ES_HOST/_cat/indices?h=index" | sort)

# 检查curl命令是否成功
if [ $? -ne 0 ]; then
    echo "错误: 无法连接到Elasticsearch服务器，请检查ES_HOST配置和网络连接"
    exit 1
fi

found=0

# 遍历每个索引，检查是否有index.store.type配置
for index in $indices; do
    # 获取索引设置
    settings=$(curl -s $AUTH_PARAM "$ES_HOST/$index/_settings")
    
    # 使用jq检查是否包含index.store.type配置
    if echo "$settings" | jq -e ".[\"$index\"].settings.index.store.type" > /dev/null 2>&1; then
        store_type=$(echo "$settings" | jq -r ".[\"$index\"].settings.index.store.type")
        echo "索引: $index"
        echo "store.type: $store_type"
        echo "----------------------------------------"
        found=1
    fi
done

if [ $found -eq 0 ]; then
    echo "未发现任何索引具有 index.store.type 配置"
fi

echo "查询完成"