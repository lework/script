#!/bin/env bash
###################################################################
#Script Name    : show_pid_openfile.sh
#Description    : Show Pid OpenFile Top 10.
#Create Date    : 2021-07-29
#Author         : lework
#Email          : lework@yeah.net
###################################################################


function printbar() {
  title=$1 
  value=$2
  
  tput setaf  $((1+ ${value} % 7))
  printf " %10s " "${title}"
  eval "printf '█%.0s' {1..${value}}"
  printf " %s %s\n\n" ${value}
  tput sgr0
}


while true
do
    # Show a title
    tput clear
    printf " %10s " ""
    tput setaf 7; tput smul;
    printf "%s\n\n" "Show Pid OpenFile Top 10 ($(date +%T))"
    tput rmul
    data=""
    for proc in $(find /proc/ -maxdepth 1 -type d -name "[0-9]*")
    do
        fd=$(ls $proc/fd 2>/dev/null | wc -l)
        if [[ $fd -gt 1 ]]; then
            pid=$(echo $proc | awk -F/ '{print $3}')
            data="${data}\n${pid} ${fd}"
        fi
    done
    echo -e ${data} | sort -k2 -n -r | head -10 | while read line
    do
       printbar $line
    done
    sleep 10
done
