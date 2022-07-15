if ps aux | grep -i '[a]liyun'; then
  curl http://update.aegis.aliyun.com/download/uninstall.sh | bash
  curl http://update.aegis.aliyun.com/download/quartz_uninstall.sh | bash
  pkill aliyun-service
  rm -rf /etc/init.d/agentwatch /usr/sbin/aliyun-service
  rm -rf /usr/local/aegis*
  systemctl stop aliyun.service
  systemctl disable aliyun.service
  service bcm-agent stop
  yum remove bcm-agent -y
  apt-get remove bcm-agent -y
elif ps aux | grep -i '[y]unjing'; then
  /usr/local/qcloud/stargate/admin/uninstall.sh
  /usr/local/qcloud/YunJing/uninst.sh
  /usr/local/qcloud/monitor/barad/admin/uninstall.sh
fi
if [ -f /usr/local/cloudmonitor/wrapper/bin/cloudmonitor.sh ]; then
  /usr/local/cloudmonitor/wrapper/bin/cloudmonitor.sh stop && /usr/local/cloudmonitor/wrapper/bin/cloudmonitor.sh remove && rm -rf /usr/local/cloudmonitor	
else
  export ARCH=amd64
  if [ -f /usr/local/cloudmonitor/CmsGoAgent.linux-${ARCH} ]; then
    /usr/local/cloudmonitor/CmsGoAgent.linux-${ARCH} stop && /usr/local/cloudmonitor/CmsGoAgent.linux-${ARCH} uninstall && rm -rf /usr/local/cloudmonitor	
  else
    echo "ali cloud monitor not running"
  fi
fi