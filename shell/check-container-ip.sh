#!/usr/bin/env bash
###################################################################
#Script Name    : check-container-ip.sh
#Description    : Detect container ip addresses and dynamically update nginx upstream configuration
#Create Date    : 2021-06-25
#Author         : lework
#Email          : lework@yeah.net
###################################################################


[[ -n $DEBUG ]] && set -x
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline


######################################################################################################
# environment configuration
######################################################################################################

RETRIES="${RETRIES:-9223372036854775807}"
WAIT="${WAIT:-5}"

CONTAINER_NAME="${CONTAINER_NAME:-}"
CONFIG_FILE="${CONFIG_FILE:-}"
CONFIG_FILE_NAME="${CONFIG_FILE_NAME:-}"
UPSTREAM_NAME="${UPSTREAM_NAME:-}"
SERVICE_PORT="${SERVICE_PORT:-}"
CONTAINER_IP="${CONTAINER_IP:-}"
CHECK_IP="${CHECK_IP:-}"
NGINX_STATUS=0 # 为1时reload nginx
NOTICE_TYPE="${NOTICE_TYPE:-feishu}"
NOTICE_MESSAGE="${NOTICE_MESSAGE:-}"
NOTICE_TOKEN="${NOTICE_TOKEN:-}"

TMP_DIR="$(rm -rf /tmp/check-container-ip* && mktemp -d -t check-container-ip.XXXXXXXXXX)"
TMP_CONFIG_FILE="${TMP_DIR}/${CONFIG_FILE_NAME}_$(date +%s)_temp.conf"

NGINX_BACKUP_PATH="${NGINX_BACKUP_PATH:-/tmp}"

trap trap::info 1 2 3 15 EXIT

######################################################################################################
# function
######################################################################################################

function trap::info() {
  # 信号处理
  
  [ ${n:-0} -gt 0 ] && log::info "[stop]" "check total: ${n}"

  trap '' EXIT
  exit
}


function log::error() {
  # 错误日志
  
  printf "[%s]: \033[31mERROR:   \033[0m%s\n" "$(date +'%Y-%m-%dT%H:%M:%S.%N%z')" "$*"
}


function log::info() {
  # 基础日志
  
  printf "[%s]: \033[32mINFO:    \033[0m%s\n" "$(date +'%Y-%m-%dT%H:%M:%S.%N%z')" "$*"
}


function log::warning() {
  # 警告日志
  
  printf "[%s]: \033[33mWARNING: \033[0m%s\n" "$(date +'%Y-%m-%dT%H:%M:%S.%N%z')" "$*"
}


function container::get_ip() {
  # 获取容器 ip地址
  
  log::info "[container]" "Get container ip address."
  container_id=$(docker ps -a --no-trunc --filter=status=running --format "table {{.ID}}\t{{.Names}}" | awk "/${CONTAINER_NAME}/{print \$1}")
  CONTAINER_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${container_id} 2>/dev/null | tr  '\n' ' ' )
  if [[ "$?" != "0" || "${CONTAINER_IP}" == "" ]]; then
      log::error "[container]" "Get container ip address error."
      exit 1
  fi
  
  log::info "[container]" "IP: ${CONTAINER_IP}"
}

function container::check_ip() {
  # 检测容器ip地址
  
  log::info "[container]" "Check container service status."
  CHECK_IP=""
  for ip in ${CONTAINER_IP}; do
    curl -s --output /dev/null "http://${ip}:${SERVICE_PORT}" && CHECK_IP="${CHECK_IP} ${ip}"
  done
  log::info "[container]" "Check success: ${CHECK_IP}"
}

function nginx::get_upstream_ip() {
  # 获取 nginx upstream ip地址
  
  log::info "[nginx]" "Get nginx upstream ${UPSTREAM_NAME} host."
  upstream_ip=$(awk '-F *|:' "                                  
/upstream ${UPSTREAM_NAME}/  {
                               app = 1 
                               next
                             }
/server/                     { 
                               if (app) print \$3
                             }
/}/                          { 
                               if (app) exit
                             }
" "${CONFIG_FILE}" | tr '\n' ' ')
  log::info "[nginx]" "Upstream host: ${upstream_ip}"
}

function nginx::config() {
  # 配置 nginx
  
  log::info "[nginx]" "Config nginx upstream ${UPSTREAM_NAME} host."

  cp "${CONFIG_FILE}" "${TMP_CONFIG_FILE}"
  for ip in ${CHECK_IP}; do
    if ! grep "${ip}" "${TMP_CONFIG_FILE}" >/dev/null 2>&1; then
      sed -i "/upstream ${UPSTREAM_NAME} {/a\    server ${ip}:${SERVICE_PORT};" "${TMP_CONFIG_FILE}" && NGINX_STATUS=1
      log::info "[nginx]" "IP: ${ip} add to upstream hosts."
      NOTICE_MESSAGE="${NOTICE_MESSAGE}**Add**: ${ip} add to upstream hosts.\n"
    fi
  done
 
  for ip in ${upstream_ip}; do
    if [[ "$CHECK_IP" == *${ip}* ]]; then
      log::info "[nginx]" "IP: ${ip} ip already exists on the upstream host."
    else
      log::info "[nginx]" "IP: ${ip} delete from upstream host."
      NOTICE_MESSAGE="${NOTICE_MESSAGE}**Del**: ${ip} delete from upstream host.\n"
      sed -i "/server ${ip:-11111111111}:${SERVICE_PORT}/d" "${TMP_CONFIG_FILE}" && NGINX_STATUS=1
    fi
  done

  if [[ $NGINX_STATUS == 1 ]]; then
    log::info "[nginx]" "Backup nginx config to ${NGINX_BACKUP_PATH}/${CONFIG_FILE_NAME}-$(date +%s)"
    cp -f "$CONFIG_FILE" "${NGINX_BACKUP_PATH}/${CONFIG_FILE_NAME}-$(date +%s)"
    log::info "[nginx]" "Apply nginx config file."
    mv -f "${TMP_CONFIG_FILE}" "$CONFIG_FILE"
  fi
}


function nginx::reload() {
  # 重载 nginx
  
  if [[ $NGINX_STATUS == 1 ]]; then
    log::info "[nginx]" "Reload nginx."
    local level=red
    if nginx -t >/dev/null 2>&1; then
      if nginx -s reload >/dev/null 2>&1; then
        log::info "[nginx]" "Reload nginx success."
        NOTICE_MESSAGE="${NOTICE_MESSAGE}**Reload**: nginx success.\n"
        level=green
      else
        log::error "[nginx]" "Reload nginx error."
        NOTICE_MESSAGE="${NOTICE_MESSAGE}**Reload**: nginx error.\n"
      fi
    else
      log::error "[nginx]" "test nginx config error."
      NOTICE_MESSAGE="${NOTICE_MESSAGE}**Test**: nginx config error.\n"
      exit 1
    fi 
    notice "$level" "${NOTICE_MESSAGE}" 
  fi
}

function notice() {
  # 通知
  
  log::info "[notice]" "select ${NOTICE_TYPE}"
  if [ -z $NOTICE_TOKEN ];then
     log::warning "[notice]" "please set NOTICE_TOKEN"
     return
  fi
  notice::${NOTICE_TYPE} $@
}

function notice::feishu() {
  # 飞书通知

  local level="${1:-green}"
  local message="${@:2}"
  local now_date="$(date +'%Y-%m-%d %T')"
  local title="[Upstream] check container ip"
  local host="$(ip a | grep glo | awk '{print $2}' | head -1 | cut -f1 -d/)"

  local template="{\"msg_type\":\"interactive\",\"card\":{\"config\":{\"wide_screen_mode\":true,\"enable_forward\":true},\"header\":{\"title\":{\"content\":\"$title\",\"tag\":\"plain_text\"},\"template\":\"${level}\"},\"elements\":[{\"tag\":\"div\",\"text\":{\"content\":\"**发生时间:**\",\"tag\":\"lark_md\"},\"fields\":[{\"is_short\":false,\"text\":{\"tag\":\"lark_md\",\"content\":\"${now_date}\"}}]},{\"tag\":\"div\",\"text\":{\"content\":\"**节点:**\",\"tag\":\"lark_md\"},\"fields\":[{\"is_short\":false,\"text\":{\"tag\":\"lark_md\",\"content\":\"${host}\"}}]},{\"tag\":\"div\",\"text\":{\"content\":\"**详细信息:**\",\"tag\":\"lark_md\"},\"fields\":[{\"is_short\":false,\"text\":{\"tag\":\"lark_md\",\"content\":\"${message}\"}}]},{\"tag\":\"hr\"},{\"tag\":\"note\",\"elements\":[{\"tag\":\"plain_text\",\"content\":\"by lework\"}]}]}}"
  
  if curl -s -X POST -H "Content-Type: application/json" -d "${template}" "https://open.feishu.cn/open-apis/bot/v2/hook/${NOTICE_TOKEN}" | grep success >/dev/null 2>&1; then
    log::info "[notice]" "send feishu success."
  else
    log::error "[notice]" "send feishu error."
  fi
}

function check::start() {
  # 检测流程
  
  echo 
  log::info "[check]" "Start inspection."
  
  container::get_ip
  container::check_ip
  nginx::get_upstream_ip

  nginx::config
  nginx::reload

  NGINX_STATUS=0
  NOTICE_MESSAGE=""
}

function help::usage {
  # 使用帮助
  
  cat << EOF

Detect container ip addresses and dynamically update nginx upstream configuration.

Usage:
  $(basename "$0") [options]

Options:
  --container-name  Docker container name
  --config-file     Nginx conf path
  --upstream-name   Nginx upstream name
  --service-port    Service port
  --retries         Retries number, default:${RETRIES}
  --wait            Retries wait time, default:${WAIT}
  -h,--help         View help

Example:
  $0 --container-name api-test \\
     --config-file /etc/nginx/conf.d/api.conf \\
     --upstream-name api \\
     --service-port 8000 \\
     --retries 20 \\
     --wait 5

EOF
  exit 1
}



######################################################################################################
# main
######################################################################################################

[ "$#" == "0" ] && help::usage

while [ "${1:-}" != "" ]; do
  case $1 in
    --container-name )      shift
                            CONTAINER_NAME=${1:-$CONTAINER_NAME}
                            ;;
    --config-file )         shift
                            CONFIG_FILE=${1:-$CONFIG_FILE}
                            CONFIG_FILE_NAME=$(basename ${CONFIG_FILE})
                            ;;
    --upstream-name )       shift
                            UPSTREAM_NAME=${1:-$UPSTREAM_NAME}
                            ;;
    --service-port )        shift
                            SERVICE_PORT=${1:-$SERVICE_PORT}      
                            ;;
    --retries )             shift
                            RETRIES=${1:-$RETRIES}
                            ;;
    --wait )                shift
                            WAIT=${1:-$WAIT}
                            ;;
    -h | --help )           help::usage
                            ;;
    * )                     help::usage
                            exit 1
  esac
  shift
done

n=0
while [[ $n -lt ${RETRIES} ]]
do
    check::start
    sleep ${WAIT}
    let n++
done

