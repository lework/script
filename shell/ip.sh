#!/bin/bash


get_ip_from_doh() {
   local domain=${1:-www.baidu.com}
   local dohs=(doh.defaultroutes.de dns.hostux.net uncensored.lux1.dns.nixnet.xyz dns.rubyfish.cn dns.alidns.com doh.centraleu.pi-dns.com doh.dns.sb doh-fi.blahdns.com fi.doh.dns.snopyta.org dns.flatuslifir.is doh.li dns.digitale-gesellschaft.ch)
   ip=$(curl -4fsSLkA- -m200 "https://${dohs[$((RANDOM%10))]}/dns-query?name=${domain}" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" |tr ' ' '\n'|grep -Ev [.]0|sort -uR|head -1)
   echo "${domain}: ${ip}"
}

get_addr () {
    local if_name=$1
    local uri_template=$2
    ip addr show dev $if_name | awk -v uri=$uri_template '/\s*inet\s/ { \
      ip=gensub(/(.+)\/.+/, "\\1", "g", $2); \
      print gensub(/^(.+:\/\/).+(:.+)$/, "\\1" ip "\\2", "g", uri); \
      exit}'
}

# converts IPv4 as "A.B.C.D" to integer
ip4_to_int() {
  IFS=. read -r i j k l <<EOF
$1
EOF
  echo $(( (i << 24) + (j << 16) + (k << 8) + l ))
}

# converts interger to IPv4 as "A.B.C.D"
int_to_ip4() {
  echo "$(( ($1 >> 24) % 256 )).$(( ($1 >> 16) % 256 )).$(( ($1 >> 8) % 256 )).$(( $1 % 256 ))"
}

# returns the ip part of an CIDR
cidr_ip() {
  IFS=/ read -r ip _ <<EOF
$1
EOF
  echo $ip
}

# returns the prefix part of an CIDR
cidr_prefix() {
  IFS=/ read -r _ prefix <<EOF
$1
EOF
  echo $prefix
}

# returns net mask in numberic from prefix size
netmask_of_prefix() {
  echo $((4294967295 ^ (1 << (32 - $1)) - 1))
}

# returns default gateway address (network address + 1) from CIDR
cidr_default_gw() {
  ip=$(ip4_to_int $(cidr_ip $1))
  prefix=$(cidr_prefix $1)
  netmask=$(netmask_of_prefix $prefix)
  gw=$((ip & netmask + 1))
  int_to_ip4 $gw
}

# returns default gateway address (broadcast address - 1) from CIDR
cidr_default_gw_2() {
  ip=$(ip4_to_int $(cidr_ip $1))
  prefix=$(cidr_prefix $1)
  netmask=$(netmask_of_prefix $prefix)
  broadcast=$(((4294967295 - netmask) | ip))
  int_to_ip4 $((broadcast - 1))
}


ip4_to_int 192.168.0.1
# => 3232235521

int_to_ip4 3232235521
# => 192.168.0.1


# network address
ip=$(ip4_to_int 172.16.10.20)
netmask=$(ip4_to_int 255.255.252.0)
int_to_ip4 $((ip & netmask))
# => 172.16.8.0


# broadcast address
ip=$(ip4_to_int 172.16.10.20)
netmask=$(ip4_to_int 255.255.252.0)
int_to_ip4 $(((ip & netmask) + 1))
# => 172.16.8.1


cidr_ip "172.16.0.10/22"
# => 172.16.0.10

cidr_prefix "172.16.0.10/22"
# => 22

netmask_of_prefix 8
# => 4278190080


cidr_default_gw 192.168.10.1/24
# => 192.168.10.1
cidr_default_gw 192.168.10.1/16
# => 192.168.0.1
cidr_default_gw 172.17.18.19/20
# => 172.17.16.1


cidr_default_gw_2 192.168.10.1/24
# => 192.168.10.254
cidr_default_gw_2 192.168.10.1/16
# => 192.168.255.254
cidr_default_gw_2 172.17.18.19/20
# => 172.17.31.254