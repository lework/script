

function e() {
  # 快速进入容器命名空间
  # exp: e POD_NAME NAMESPACE
  set -eu
  pod_name=${1}
  ns=${2-"default"}
  host_ip=$(kubectl -n $ns get pod $pod_name -o jsonpath='{.status.hostIP}')
  container_id=$(kubectl -n $ns describe pod $pod_name | grep -A10 "^Containers:" | grep -Eo 'docker://.*$' | head -n 1 | sed 's/docker:\/\/\(.*\)$/\1/')
  container_pid=$(docker inspect -f {{.State.Pid}} $container_id)
  cmd="nsenter -n --target $container_pid"
  echo "entering pod netns for [${host_ip}] $ns/$pod_name"
  echo $cmd
  $cmd
}