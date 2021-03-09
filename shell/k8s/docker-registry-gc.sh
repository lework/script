#!/bin/bash

v2=$1
v2=${v2:="/var/lib/registry/docker/registry/v2"}
all_blobs=/tmp/all_blobs.list

cd ${v2}

: > ${all_blobs}

# delete unlink blob's link file in _layers
for link in $(find repositories -type f -name "link" | grep -E "_layers\/sha256\/.*"); do
    link_sha256=$(echo ${link} | grep -Eo "_layers\/sha256\/.*" | sed 's/_layers\/sha256\///g;s/\/link//g')
    link_short=${link:0:2}
    link_dir=$(echo ${link} | sed 's/\/link//')
    data_file=blobs/sha256/${link_short}/${link}
    if [[ ! -d ${data_file} ]]; then echo "Del link: ${link_dir}"; rm -rf ${link_dir}; fi
done

#marking all the blob by all images manifest
for tag in $(find repositories -name "link" | grep current); do
    link=$(cat ${tag} | cut -c8-71)
    mfs=blobs/sha256/${link:0:2}/${link}/data
    echo ${link} >> ${all_blobs}
    grep -Eo "\b[a-f0-9]{64}\b" ${mfs} | sort -n | uniq | cut -c1-12 >> ${all_blobs}
done

#delete blob if the blob doesn't exist in all_blobs.list
for blob in $(find blobs -name "data" | cut -d "/" -f4); do
    if ! grep ${blob} ${all_blobs}; then
        echo "Del blob: blobs/sha256/${blob:0:2}/${blob}"
        rm -rf blobs/sha256/${blob:0:2}/${blob}
    fi
done