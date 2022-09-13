#!/usr/bin/env bash

set -x
current_dir=$(pwd)
timestamp=$(date +%s)
diagnose_dir=/tmp/diagnose_${timestamp}
mkdir -p $diagnose_dir
is_ps_hang=false

run() {
    echo
    echo "-----------------run $@------------------"
    timeout 10s $@
    if [ "$?" != "0" ]; then
        echo "failed to collect info: $@"
    fi
    echo "------------End of ${1}----------------"
}

os_env()
{
    grep -q "Ubuntu" /etc/os-release && export OS="Ubuntu" && return
    grep -q "SUSE" /etc/os-release && export OS="SUSE" && return
    grep -q "Red Hat" /etc/os-release && export OS="RedHat" && return
    grep -q "CentOS Linux" /etc/os-release && export OS="CentOS" && return
    grep -q "Kylin Linux" /etc/os-release && export OS="CentOS" && return
    grep -q "Aliyun Linux" /etc/os-release && export OS="AliyunOS" && return
    grep -q "Alibaba Group Enterprise Linux" /etc/os-release && export OS="AliOS" && return

    echo "unknown os...  exit."
    exit 1
}

dist() {
    cat /etc/issue*
}

command_exists() {
    command -v "$@" > /dev/null 2>&1
}

# Service status
service_status() {
    run service firewalld status | tee $diagnose_dir/service_status
    run service ntpd status | tee $diagnose_dir/service_status
    run service chronyd status | tee $diagnose_dir/service_status
}


#system info

system_info() {
    # mkdir -p ${diagnose_dir}/system_info
    run uname -a | tee -a ${diagnose_dir}/system_info
    run uname -r | tee -a ${diagnose_dir}/system_info
    run dist | tee -a ${diagnose_dir}/system_info
    if command_exists lsb_release; then
        run lsb_release | tee -a ${diagnose_dir}/system_info
    fi
    run ulimit -a | tee -a ${diagnose_dir}/system_info
    run sysctl -a | tee -a ${diagnose_dir}/system_info
}

#network
network_info() {
    # mkdir -p ${diagnose_dir}/network_info
    #run ifconfig
    run ip --details ad show | tee -a ${diagnose_dir}/network_info
    run ip --details link show | tee -a ${diagnose_dir}/network_info
    run ip route show | tee -a ${diagnose_dir}/network_info
    run iptables-save | tee -a ${diagnose_dir}/network_info
    netstat -nt | tee -a ${diagnose_dir}/network_info
    netstat -nu | tee -a ${diagnose_dir}/network_info
    netstat -ln | tee -a ${diagnose_dir}/network_info
}


# check ps -ef command is hung
check_ps_hang() {
  echo "check if ps -ef command hang" | tee -a ${diagnose_dir}/ps_command_status
  checkD=$(timeout -s 9 2 ps -ef)
  if [ "$?" != "0" ]; then
      echo "ps -ef command is hung" | tee -a ${diagnose_dir}/ps_command_status
      is_ps_hang=true
      echo "start to check which process lead to ps -ef command hang" | tee -a ${diagnose_dir}/ps_command_status
      for f in `find /proc/*/task -name status`
      do
          checkD=$(cat $f|grep "State.*D")
          if [ "$?" == "0" ]; then
              cmdline=$(echo ${f%%status}"cmdline")
              pid=$(echo ${f%%status}"")
              stack=$(echo ${f%%status}"stack")
              timeout -s 9 2 cat $cmdline
              if [ "$?" != "0" ]; then
                  echo "process $pid is in State D and lead to ps -ef process hang,stack info:" | tee -a ${diagnose_dir}/ps_command_status
                  cat $stack | tee -a ${diagnose_dir}/ps_command_status
              fi
          fi
      done
      echo "finish to check which process lead to ps -ef command hang" | tee -a ${diagnose_dir}/ps_command_status
  else
      echo "ps -ef command works fine" | tee -a ${diagnose_dir}/ps_command_status
  fi
}


#system status
system_status() {
    #mkdir -p ${diagnose_dir}/system_status
    run uptime | tee -a ${diagnose_dir}/system_status
    run top -b -n 1 | tee -a ${diagnose_dir}/system_status
    if [ "$is_ps_hang" == "false" ]; then
        run ps -ef | tee -a ${diagnose_dir}/system_status
    else
        echo "ps -ef command hang, skip [ps -ef] check" | tee -a ${diagnose_dir}/system_status
    fi
    run netstat -nt | tee -a ${diagnose_dir}/system_status
    run netstat -nu | tee -a ${diagnose_dir}/system_status
    run netstat -ln | tee -a ${diagnose_dir}/system_status

    run df -h | tee -a ${diagnose_dir}/system_status

    run cat /proc/mounts | tee -a ${diagnose_dir}/system_status

    if [ "$is_ps_hang" == "false" ]; then
        run pstree -al | tee -a ${diagnose_dir}/system_status
    else
        echo "ps -ef command hang, skip [pstree -al] check" | tee -a ${diagnose_dir}/system_status
    fi

    run lsof | tee -a ${diagnose_dir}/system_status

    (
        cd /proc
        find -maxdepth 1 -type d -name '[0-9]*' \
         -exec bash -c "ls {}/fd/ | wc -l | tr '\n' ' '" \; \
         -printf "fds (PID = %P), command: " \
         -exec bash -c "tr '\0' ' ' < {}/cmdline" \; \
         -exec echo \; | sort -rn | head | tee -a ${diagnose_dir}/system_status
    )
}


daemon_status() {
     run systemctl status docker -l | tee -a ${diagnose_dir}/docker_status
     run systemctl status containerd -l | tee -a ${diagnose_dir}/containerd_status
     run systemctl status container-storaged -l | tee -a ${diagnose_dir}/container-storaged_status
     run systemctl status kubelet -l | tee -a ${diagnose_dir}/kubelet_status
}

docker_status() {
    #mkdir -p ${diagnose_dir}/docker_status
    echo "check dockerd process"
    if [ "$is_ps_hang" == "false" ]; then
        run ps -ef|grep -E 'dockerd|docker daemon'|grep -v grep| tee -a ${diagnose_dir}/docker_status
    else
        echo "ps -ef command hang, skip [ps -ef|grep -E 'dockerd|docker daemon'] check" | tee -a ${diagnose_dir}/docker_status
    fi

    #docker info
    run docker info | tee -a ${diagnose_dir}/docker_status
    run docker version | tee -a ${diagnose_dir}/docker_status
    sudo kill -SIGUSR1 $(cat /var/run/docker.pid)
    cp /var/run/docker/libcontainerd/containerd/events.log ${diagnose_dir}/containerd_events.log
    sleep 10
    cp /var/run/docker/*.log ${diagnose_dir}

}

showlog() {
    local file=$1
    if [ -f "$file" ]; then
        tail -n 200 $file
    fi
}

#collect log
common_logs() {
    log_tail_lines=10000
    mkdir -p ${diagnose_dir}/logs
    run dmesg -T | tail -n ${log_tail_lines}  | tee ${diagnose_dir}/logs/dmesg.log
    tail -c 500M /var/log/messages &> ${diagnose_dir}/logs/messages
    pidof systemd && journalctl -n ${log_tail_lines} -u docker.service &> ${diagnose_dir}/logs/docker.log || tail -n ${log_tail_lines} /var/log/upstart/docker.log &> ${diagnose_dir}/logs/docker.log
}

archive() {
    tar -zcvf ${current_dir}/diagnose_${timestamp}.tar.gz ${diagnose_dir}
    echo "please get diagnose_${timestamp}.tar.gz for diagnostics"
}

varlogmessage(){
    grep cloud-init /var/log/messages > $diagnose_dir/varlogmessage.log
}

cluster_dump(){
    kubectl cluster-info dump > $diagnose_dir/cluster_dump.log
}

events(){
    kubectl get events > $diagnose_dir/events.log
}

core_component() {
    local comp="$1"
    local label="$2"
    mkdir -p $diagnose_dir/cs/$comp/
    local pods=`kubectl get -n kube-system po -l $label=$comp | awk '{print $1}'|grep -v NAME`
    for po in ${pods}
    do
        kubectl logs -n kube-system ${po} &> $diagnose_dir/cs/${comp}/${po}.log
    done
}

etcd() {
    journalctl -u etcd -xe &> $diagnose_dir/cs/etcd.log
}

storageplugins() {
    mkdir -p ${diagnose_dir}/storage/
    cp /var/log/alicloud/* ${diagnose_dir}/storage/
}

sandbox_runtime_status() {
    if [[ ! -z $(pidof dockerd) || -z $(pidof containerd) ]]; then
        return 0
    fi
    wget http://aliacs-k8s-cn-hangzhou.oss-cn-hangzhou.aliyuncs.com/public/diagnose/sandbox-runtime-status.tgz -q -O ${diagnose_dir}/sandbox-runtime-status.tgz
    tar -xzvf ${diagnose_dir}/sandbox-runtime-status.tgz -C ${diagnose_dir}
    pushd ${diagnose_dir}/sandbox-runtime-status
    bash script_collect.sh >> $diagnose_dir/sandbox_runtime.status
    popd
}

upload_oss() {
  if [[ "$UPLOAD_OSS" == "" ]]; then
      return 0
  fi

  bucket_path=${UPLOAD_OSS}
  diagnose_file=diagnose_${timestamp}.tar.gz

  if ! command_exists ossutil; then
    curl -o /usr/local/bin/ossutil http://gosspublic.alicdn.com/ossutil/1.6.10/ossutil64
    chmod u+x /usr/local/bin/ossutil
  fi


  region=$(curl http://100.100.100.200/latest/meta-data/region-id)
  endpoint="oss-$region.aliyuncs.com"
  if [[ "$ACCESS_KEY_ID" == "" ]]; then
    roleName=$(curl 100.100.100.200/latest/meta-data/ram/security-credentials/)
    echo "
[Credentials]
        language = CH
        endpoint = $endpoint
[AkService]
        ecsAk=http://100.100.100.200/latest/meta-data/Ram/security-credentials/$roleName" > ./config
  else
    echo "
[Credentials]
        language = CH
        endpoint = $endpoint
        accessKeyID = $ACCESS_KEY_ID
        accessKeySecret = $ACCESS_KEY_SECRET
" > ./config
  fi
  bucket_name=${bucket_path%%/*}
  oss_endpoint=$(ossutil stat oss://$bucket_name --config-file ./config | grep ExtranetEndpoint | awk '{print $3}')
  if [[ "$oss_endpoint" != "" ]]; then
    endpoint=$oss_endpoint
  fi
  ossutil cp ./${diagnose_file} oss://$bucket_path/$diagnose_file --config-file ./config --endpoint $endpoint

  if [[ "$OSS_PUBLIC_LINK" != "" ]]; then
    ossutil sign --timeout 7200 oss://$bucket_path/$diagnose_file --config-file ./config --endpoint $endpoint
  fi
}

parse_args() {
    while
        [[ $# -gt 0 ]]
    do
        key="$1"

        case $key in
        --oss)
            export UPLOAD_OSS=$2
            shift
            ;;
        --oss-public-link)
            export OSS_PUBLIC_LINK="true"
            ;;
        --access-key-id)
            export ACCESS_KEY_ID=$2
            shift
            ;;
        --access-key-secret)
            export ACCESS_KEY_SECRET=$2
            shift
            ;;
        *)
            echo "unknown option [$key]"
            ;;
        esac
        shift
    done
}

pd_collect() {
    os_env
    system_info
    service_status
    network_info
    check_ps_hang
    system_status
    docker_status
    sandbox_runtime_status
    common_logs

    varlogmessage
    core_component "cloud-controller-manager" "app"
    core_component "kube-apiserver" "component"
    core_component "kube-controller-manager" "component"
    core_component "kube-scheduler" "component"
    events
    storageplugins
    etcd
    cluster_dump
    archive
}

parse_args "$@"

pd_collect

upload_oss

echo "请上传 diagnose_${timestamp}.tar.gz"
