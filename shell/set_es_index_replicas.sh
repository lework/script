#!/bin/bash

# 设置ES索引副本数量脚本
# 功能：将副本数不为1的索引批量设置为1

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

echo "开始检查并设置ES索引副本数..."

# 测试ES连接
echo "测试ES连接..."
es_test=$(curl -s $AUTH_PARAM "${ES_HOST}/_cluster/health")
if [ $? -ne 0 ] || [ -z "$es_test" ]; then
    echo "错误: 无法连接到ES服务器，请检查地址和认证信息是否正确"
    exit 1
fi
echo "ES连接成功"

# 获取所有索引列表
indices=$(curl -s $AUTH_PARAM "${ES_HOST}/_cat/indices?h=index" | sort)

# 检查是否成功获取索引列表
if [ -z "$indices" ]; then
    echo "错误: 无法从ES服务器获取索引列表，请检查ES服务是否正常运行"
    exit 1
fi

echo "成功获取索引列表，共计$(echo "$indices" | wc -l | tr -d ' ')个索引"
echo "开始检查并设置副本数..."

# 计数器
changed_count=0
already_set_count=0
error_count=0

# 遍历每个索引
for index in $indices; do
    # 跳过系统索引
    if [[ $index == .* ]]; then
        echo "跳过系统索引: $index"
        continue
    fi
    
    # 获取当前索引的副本数
    replica_count=$(curl -s $AUTH_PARAM "${ES_HOST}/${index}/_settings" | jq -r ".[\"${index}\"].settings.index.number_of_replicas")
    
    # 检查是否成功获取副本数
    if [ -z "$replica_count" ] || [ "$replica_count" == "null" ]; then
        echo "警告: 无法获取索引 $index 的副本数设置"
        error_count=$((error_count + 1))
        continue
    fi
    
    echo "索引: $index, 当前副本数: $replica_count"
    
    # 判断副本数是否为1
    if [ "$replica_count" != "1" ]; then
        # 设置副本数为1
        echo "设置索引 $index 的副本数为1..."
        update_result=$(curl -s $AUTH_PARAM -X PUT "${ES_HOST}/${index}/_settings" -H "Content-Type: application/json" -d '{"index":{"number_of_replicas":1}}')
        
        # 检查更新结果
        if echo "$update_result" | jq -e '.acknowledged' &>/dev/null; then
            echo "成功: 索引 $index 的副本数已设置为1"
            changed_count=$((changed_count + 1))
        else
            echo "错误: 设置索引 $index 的副本数失败"
            error_count=$((error_count + 1))
        fi
    else
        # echo "索引 $index 的副本数已经是1，无需修改"
        already_set_count=$((already_set_count + 1))
    fi
done

echo "========== 操作完成 =========="
echo "总计索引数: $(echo "$indices" | wc -l | tr -d ' ')"
echo "已修改索引数: $changed_count"
echo "无需修改索引数: $already_set_count"
echo "操作失败索引数: $error_count"
echo "=============================="
