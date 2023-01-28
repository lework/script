#!/bin/env bash
# 
# lework
# Os repo mirror site speed test.


######################################################################################################
# environment configuration
######################################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

declare -A mirrors
mirrors=(
  [edu_sjtu]="http://ftp.sjtu.edu.cn/"
  [edu_ustc]="https://mirrors.ustc.edu.cn/"
  [edu_lzu]="http://mirror.lzu.edu.cn/"
  [edu_bjtu]="https://mirror.bjtu.edu.cn/"
  [edu_bit]="http://mirror.bit.edu.cn/"
  [edu_cqu]="http://mirrors.cqu.edu.cn/"
  [edu_dlut]="http://mirror.dlut.edu.cn/"
  [edu_zju]="http://mirrors.zju.edu.cn/"
  [edu_tsinghua]="https://mirrors.tuna.tsinghua.edu.cn/"
  [sohu]="http://mirrors.sohu.com/"
  [huawei]="https://mirrors.huaweicloud.com/"
  [netease]="https://mirrors.163.com/"
  [tencent]="https://mirrors.cloud.tencent.com/"
  [aliyun]="https://mirrors.aliyun.com/"
)

######################################################################################################
# function
######################################################################################################

function shutdown() {
  tput cnorm # reset cursor
}


function error() {
  ps -ef | grep "$0" | awk '{print $2}' | xargs kill -9 '{}' >/dev/null 2>&1
}

trap shutdown EXIT
trap error ERR 2 3

function spinner() {
  # make sure we use non-unicode character type locale 
  # (that way it works for any locale as long as the font supports the characters)
  local LC_CTYPE=C
  speed_test "$@" &
  sleep 1

  local pid=$(ps -ef | grep -E '[w]get.*-4O /dev/null -T300' | awk '{print $2}') # Process Id of the previous running command

  local spin='-\|/'
  local charwidth=1

  local i=0 
  tput civis # cursor invisible
  while kill -0 $pid 2>/dev/null; do
    local i=$(((i + $charwidth) % ${#spin}))
    printf "%s" "${spin:$i:$charwidth}"

    echo -en "\033[1D"
    sleep .1
  done
  tput cnorm
  wait
}

speed_test() {
    local output=$(LANG=C wget ${3:+"--header="}"$3" -4O /dev/null -T300 "$1" 2>&1)
    local speed=$(printf '%s' "$output" | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}')
    local ipaddress=$(printf '%s' "$output" | awk -F'|' '/Connecting to .*\|([^\|]+)\|/ {print $2}'| tail -1)
    local time=$(printf '%s' "$output" | awk -F= '/100% / {print $2}')
    local size=$(printf '%s' "$output" | awk '/Length:/ {s=$3} END {gsub(/\(|\)/,"",s); print s}')
    printf "${YELLOW}%-14s${GREEN}%-20s${BLUE}%-14s${PLAIN}%-20s${RED}%-14s${PLAIN}\n" "$2" "${ipaddress}" "${size}" "${time}" "${speed}" 
}


######################################################################################################
# main 
######################################################################################################

if  [ ! -e '/usr/bin/wget' ]; then
    echo "Error: wget command not found. You must be install wget command at first."
    exit 1
fi

if  [ ! -e '/usr/bin/curl' ]; then
    echo "Error: curl command not found. You must be install curl command at first."
    exit 1
fi

clear
echo -e "\n\nOs repo mirror site speed test"

os=`cat /etc/*-release | grep '^ID=' | \
  sed 's/^ID=["]*\([a-zA-Z]*\).*$/\1/' | \
  tr '[:upper:]' '[:lower:]'`

os=${os:-centos}
case "$os" in
  centos)
    file="centos/filelist.gz"
    ;;
  debian)
    file="/debian/ls-lR.gz"
    ;;
  *)
    file="centos/filelist.gz"
    ;;
esac

echo -e "\n[Mirror Site]"
for mirror in ${!mirrors[*]}; do
  printf "${PLAIN}%-14s${GREEN}%-20s${PLAIN}\n" ${mirror} ":  ${mirrors[$mirror]}"
done

echo -e "\n[Test]"
echo -e "Test OS       : ${YELLOW}${os}${PLAIN}"
echo -e "Download File : ${YELLOW}${file}${PLAIN}"

echo
printf "%-14s%-20s%-14s%-20s%-14s\n" "Site Name" "IPv4 address" "File Size" "Download Time" "Download Speed"
for mirror in ${!mirrors[*]}; do
  spinner "${mirrors[$mirror]}${file}" ${mirror}
done
echo
