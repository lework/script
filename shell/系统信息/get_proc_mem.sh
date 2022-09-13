#!/usr/bin/env bash
###################################################################
#Script Name    : get_proc_mem.sh
#Description    : Get Process Memory information.
#Create Date    : 2020-10-15
#Author         : lework
#Email          : lework@yeah.net
###################################################################


[[ -n $DEBUG ]] && set -x || true
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline


######################################################################################################
# environment configuration
######################################################################################################

PID="${PID:-1}"
RETRIES="${RETRIES:-0}"
WAIT="${WAIT:-1}"

COLOR_RED="${COLOR_RED:-\e[1;31m}"
COLOR_GREEN="${COLOR_GREEN:-\e[1;32m}"
COLOR_YELLOW="${COLOR_RED:-\e[1;33m}"
COLOR_BLUE="${COLOR_BLUE:-\e[1;34m}"
COLOR_PURPLE="${COLOR_PURPLE:-\e[1;35m}"
COLOR_CYAN="${COLOR_CYAN:-\e[1;36m}"
COLOR_GRAY="${COLOR_GRAY:-\e[1;90m}"
COLOR_OFF="${COLOR_OFF:-\e[0m}"
NOCOLOR="${NOCOLOR:-false}"

time_data=""
mem_total_data=""
mem_free_data=""
mem_available_data=""
mem_rss_data=""
mem_pss_data=""
mem_uss_data=""
cpu_used_data=""

trap trap::info 1 2 3 15 EXIT

######################################################################################################
# function
######################################################################################################

function trap::info() {
  cat << EOF > pid_${PID}_line.json
option = {
    title: {
        text: '内存监控',
        subtext: 'PID: ${PID}'
    },
    tooltip: {
        trigger: 'axis'
    },
    legend: {
        data: ['mem_total', 'mem_free', 'mem_available', 'pid_mem_rss', 'pid_mem_pss', 'pid_mem_uss', 'pid_cpu_used']
    },
    grid: {
        left: '3%',
        right: '4%',
        bottom: '3%',
        containLabel: true
    },
    toolbox: {
        feature: {
            saveAsImage: {}
        }
    },
    xAxis: {
        type: 'category',
        boundaryGap: false,
        data: [${time_data/,}]
    },
    yAxis: [
      	{
	    	type: "value",
	    	name: "内存 / MB",
	    	nameLocation: 'center',
	    	nameGap: 45
		},
		{
	    	type: "value",
	    	name: "CPU使用率 / %",
	    	nameLocation: 'center',
	    	nameGap: 45
		}
    ], 
    series: [
        {
            name: 'mem_total',
            type: 'line',
            smooth: true,
            data: [${mem_total_data/,}],
            markPoint: {
                data: [{
                    name: '最大值',
                    type: 'max'
                }] 
            }
        },
        {
            name: 'mem_free',
            type: 'line',
            smooth: true,
            data: [${mem_free_data/,}],
            markPoint: {
                data: [{
                    name: '最小值',
                    type: 'min'
                }] 
            }
        },
        {
            name: 'mem_available',
            type: 'line',
            smooth: true,
            data: [${mem_available_data/,}],
            markPoint: {
                data: [{
                    name: '最小值',
                    type: 'min'
                }] 
            }
        },
        {
            name: 'pid_mem_rss',
            type: 'line',
            smooth: true,
            data: [${mem_rss_data/,}],
            markPoint: {
                data: [{
                    name: '最大值',
                    type: 'max'
                }] 
            }
        },
        {
            name: 'pid_mem_pss',
            type: 'line',
            smooth: true,
            data: [${mem_pss_data/,}],
            markPoint: {
                data: [{
                    name: '最大值',
                    type: 'max'
                }] 
            }
        },
        {
            name: 'pid_mem_uss',
            type: 'line',
            smooth: true,
            data: [${mem_uss_data/,}],
            markPoint: {
                data: [{
                    name: '最大值',
                    type: 'max'
                }] 
            }
        },
        {
            name: 'pid_cpu_used',
            type: 'line',
            smooth: true,
            yAxisIndex: 1,
            data: [${cpu_used_data/,}],
            markPoint: {
                data: [{
                    name: '最大值',
                    type: 'max'
                }] 
            }
        }
    ]
};
EOF
  echo -e "
\n${COLOR_GREEN}
  Config File: pid_${PID}_line.json
  GO TO URL: https://echarts.apache.org/next/examples/en/editor.html   
${COLOR_OFF}
  "
  trap '' EXIT
  exit
            
}

######################################################################################################
# function
######################################################################################################

function get::meminfo() {

  [ ! -f "/proc/${PID}/smaps" ] && { echo -e "${COLOR_RED}[Error]${COLOR_OFF} not found $PID smaps file!"; exit 1; }  
  
  pid_smaps=$(cat /proc/${PID}/smaps)
  [ "$pid_smaps" == "" ] && { echo -e "${COLOR_RED}[Error]${COLOR_OFF} /proc/${PID}/smaps is empty!"; exit 1; }
  
  cpu_used=$(ps -opcpu= -p "${PID}")
  mem_info=$(cat /proc/meminfo)

  mem_total=$(printf "%s" "${mem_info}"| awk '/^MemTotal:/  {print $2}')
  mem_free=$(printf "%s" "${mem_info}"| awk '/^MemFree:/  {print $2}')
  mem_available=$(printf "%s" "${mem_info}"| awk '/^MemAvailable:/  {print $2}')
  size=$(printf "%s" "${pid_smaps}" | awk '/^Size/{sum += $2}END{print sum}')
  rss=$(printf "%s" "${pid_smaps}" | awk '/^Rss/{sum += $2}END{print sum}')
  pss=$(printf "%s" "${pid_smaps}" | awk '/^Pss/{sum += $2}END{print sum}')
  
  shared_clean=$(printf "%s" "${pid_smaps}" | awk '/^Shared_Clean/{sum += $2}END{print sum}')
  shared_dirty=$(printf "%s" "${pid_smaps}" | awk '/^Shared_Dirty/{sum += $2}END{print sum}')
  private_clean=$(printf "%s" "${pid_smaps}" | awk '/^Private_Clean/{sum += $2}END{print sum}')
  private_dirty=$(printf "%s" "${pid_smaps}" | awk '/^Private_Dirty/{sum += $2}END{print sum}')
  swap=$(printf "%s" "${pid_smaps}" | awk '/^Swap/{sum += $2}END{print sum}')
  swap_pss=$(printf "%s" "${pid_smaps}" | awk '/^SwapPss/{sum += $2}END{print sum}')
}


function get::pidinfo() {
    echo -e "${COLOR_PURPLE}
Pid: ${PID}
Cmd: $(tr -d '\0' < /proc/${PID}/cmdline | cut -c1-80)
User: $(id -nu < /proc/${PID}/loginuid )
Threads: $(awk '/Threads:/ {print $2}' /proc/${PID}/status)
File: /proc/${PID}/smaps
${COLOR_OFF}"

}

function get::meminfo_loop() {
  local count=0
  get::pidinfo
  while [ $count -lt $RETRIES ] ; do
    get::meminfo
    d=$(date +'%Y-%m-%d %T')
    mem_total=$((mem_total/1024))
    mem_free=$((mem_free/1024))
    mem_available=$((mem_available/1024))
    mem_rss=$((${rss}/1024))
    mem_pss=$((${pss}/1024))
    mem_uss=$(( (${private_clean} + ${private_dirty}) /1024 ))
    echo -e "Date: ${d} ${COLOR_PURPLE}MemTotal: ${mem_total}MB${COLOR_OFF} ${COLOR_GREEN}MemFree: ${mem_free}MB${COLOR_OFF} ${COLOR_BLUE}MemAvailable: ${mem_available}MB${COLOR_OFF} ${COLOR_YELLOW}RSS: ${mem_rss}MB${COLOR_OFF} ${COLOR_CYAN}PSS: ${mem_pss}MB${COLOR_OFF} ${COLOR_RED}USS: ${mem_uss}MB${COLOR_OFF} CPU: ${cpu_used}%"
    time_data="${time_data},'${d}'"
    mem_total_data="${mem_total_data},'${mem_total}'"
    mem_free_data="${mem_free_data},'${mem_free}'"
    mem_available_data="${mem_available_data},'${mem_available}'"
    mem_rss_data="${mem_rss_data},'${mem_rss}'"
    mem_uss_data="${mem_uss_data},'${mem_uss}'"
    mem_pss_data="${mem_pss_data},'${mem_pss}'"
    cpu_used_data="${cpu_used_data},'${cpu_used}'"
    sleep $WAIT
    count=$(($count + 1))
  done
}


function get::meminfo_once() {

  get::meminfo

  echo -e "${COLOR_GRAY}
# OS meminfo
MemTotal：内存总数
MemFree：空闲内存数
MemAvailable：可用内存数,包括cache/buffer、slab

# Process smaps
Size：表示该映射区域在虚拟内存空间中的大小。
Rss： 表示该映射区域当前在物理内存中占用了多少空间
      Rss=Shared_Clean+Shared_Dirty+Private_Clean+Private_Dirty
Pss： 该虚拟内存区域平摊计算后使用的物理内存大小(有些内存会和其他进程共享，例如mmap进来的)
      实际上包含下面private_clean+private_dirty，和按比例均分的shared_clean、shared_dirty。
Uss:  Unique Set Size 进程独自占用的物理内存（不包含共享库占用的内存）
      USS=Private_Clean+Private_Dirty
Shared_Clean：  和其他进程共享的未被改写的page的大小
Shared_Dirty：  和其他进程共享的被改写的page的大小
Private_Clean： 未被改写的私有页面的大小。
Private_Dirty： 已被改写的私有页面的大小。
Swap：   存在于交换分区的数据大小(如果物理内存有限，可能存在一部分在主存一部分在交换分区)
SwapPss: 计算逻辑就跟pss一样，只不过针对的是交换分区的内存。${COLOR_OFF}
"
  get::pidinfo

  echo -e "${COLOR_GREEN}# Os meminfo
MemTotal:              ${mem_total} KB
MemFree:               ${mem_free} KB
MemAvailable:          ${mem_available} KB ${COLOR_OFF}

${COLOR_CYAN}# Process smaps
Size:                  ${size} KB
RSS:                   ${rss} kB
PSS:                   ${pss} kB
Shared_Clean:          ${shared_clean} kB
Shared_Dirty:          ${shared_dirty} kB
Private_Clean:         ${private_clean} kB
Private_Dirty:         ${private_dirty} kB
Swap:                  ${swap} kB
SwapPss:               ${swap_pss} kB

USS:                   ${private_clean} + ${private_dirty} = $(( ${private_clean} + ${private_dirty} )) kB
${COLOR_OFF}
"
}

function help::usage {
  cat << EOF
  
Get Process Memory information.

Usage:
  $(basename $0) [options]
  
Options:
  -p,--pid         Process id
  -r,--retries     Retries number
  -w,--wait        Retries wit time
  -h,--help        View help
  --nocolor        Do not output color

EOF
 exit
}
######################################################################################################
# main 
######################################################################################################

#[ "$#" == "0" ] && help::usage

while [ "${1:-}" != "" ]; do
  case $1 in
    -p | --pid )            shift
                            PID=${1:-$PID}
                            ;;
    -r | --retries )        shift
                            RETRIES=${1:-$RETRIES}
                            ;;
    -w | --wait )           shift
                            WAIT=${1:-$WAIT}
                            ;;
    -h | --help )           help::usage
                            ;;
    --nocolor )             NOCOLOR=true
                            ;;
    * )                     help::usage
                            exit 1
  esac
  shift
done


if [ "${NOCOLOR}" == "true" ]; then
  COLOR_RED=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_BLUE=""
  COLOR_PURPLE=""
  COLOR_CYAN=""
  COLOR_GRAY=""
  COLOR_OFF=""
fi

if [[ ${RETRIES} -gt 0 ]]; then
 get::meminfo_loop
else
 get::meminfo_once
fi
