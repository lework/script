#!/usr/bin/env bash
###################################################################
#Script Name	: k8s-backup.sh
#Description	: backup k8s resources.
#Create Date    : 2020-11-19
#Author       	: lework
#Email         	: lework@yeah.net
###################################################################
# https://github.com/pieterlange/kube-backup/blob/master/entrypoint.sh


[[ -n $DEBUG ]] && set -x || true
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline


######################################################################################################
# environment configuration
######################################################################################################

KUBECONFIG="${HOME:-'~'}/.kube/config" # kubenetes config
NAMESPACE="${NAMESPACE:-all}"
RESOURCES="${RESOURCES:-all}"
WITH_CLUSTER="true"
RESOURCES_PATH="/opt/k8s-backup_$(date +%s)"

######################################################################################################
# function
######################################################################################################


function get::resource() {
  ns=${1:-cluster}
  namespaced="true"

  if [[ "$ns" == "cluster" ]]; then
    namespaced="false"
    [ -d "$RESOURCES_PATH/cluster" ] || mkdir -p "$RESOURCES_PATH/cluster"
  fi

  if [[ "${RESOURCES}" == "all" ]]; then
    RESOURCES=$($kubectl api-resources --verbs=list --namespaced=${namespaced} -o name | grep -v "events.events.k8s.io" | grep -v "events" | sort | uniq)
  fi
  for r in ${RESOURCES}; do
    echo "Resource:" $r
    for l in $($kubectl -n ${ns} get --ignore-not-found ${r} -o jsonpath="{$.items[*].metadata.name}");do
      $kubectl -n ${ns} get --ignore-not-found ${r} ${l} -o yaml \
        | sed -n "/ managedFields:/{p; :a; N; / name: ${l}/!ba; s/.*\\n//}; p" \
        | sed -e 's/ uid:.*//g' \
           -e 's/ resourceVersion:.*//g' \
           -e 's/ selfLink:.*//g' \
           -e 's/ creationTimestamp:.*//g' \
           -e 's/ managedFields:.*//g' \
           -e '/^\s*$/d' > "$RESOURCES_PATH/${ns}/${l}_${r}.yaml"
    done
  done
}

function get::namespace() {
  if [[ "${RESOURCES}" == "all" ]]; then
     NAMESPACE=$($kubectl get ns -o jsonpath="{$.items[*].metadata.name}")
  fi
  for n in ${NAMESPACE};do
    echo "Namespace:" $n
    [ -d "$RESOURCES_PATH/$n" ] || mkdir -p "$RESOURCES_PATH/$n"
    $kubectl get ns ${n} --ignore-not-found -o yaml \
      | sed -n "/ managedFields:/{p; :a; N; / name: ${n}/!ba; s/.*\\n//}; p" \
      | sed -e 's/ uid:.*//g' \
         -e 's/ resourceVersion:.*//g' \
         -e 's/ selfLink:.*//g' \
         -e 's/ creationTimestamp:.*//g' \
         -e 's/ managedFields:.*//g' \
         -e '/^\s*$/d' > "$RESOURCES_PATH/${n}/namespace.yaml"
    get::resource $n
  done
}

function help::usage {
  # 使用帮助
  
  cat << EOF

backup k8s resource.

Usage:
  $(basename $0) [flag]
  
Flag:
  -c,--kubeconfig  Specify kubeconfig, default is ${HOME:-~}/.kube/config
  -ns,--namespace  namespace, default: all
  -r,--resource    resource, default: all
  --with-cluster   cluster resource.
  -h,--help        help info.
EOF

 exit 1
}
 
######################################################################################################
# main
######################################################################################################


while [ "${1:-}" != "" ]; do
  case $1 in
    -c | --kubeconfig )     shift
                            KUBECONFIG=${1:-$KUBECONFIG}
                            ;;
    -ns | --namespace )     shift
                            NAMESPACE=${1:-$NAMESPACE}
                            ;;
    -r  | --resource )      shift
                            RESOURCES=${1:-$RESOURCES}
                            ;;
    --with-cluster )        shift
                            WITH_CLUSTER=${1:-$WITH_CLUSTER}
                            ;;
    -h  | --help )          help::usage
                            ;;
    * )                     help::usage
  esac
  shift
done

kubectl="kubectl --kubeconfig $KUBECONFIG"

#get::namespace
[[ "$WITH_CLUSTER" == "true" ]] && get::resource cluster || echo

echo "File: ${RESOURCES_PATH}"
