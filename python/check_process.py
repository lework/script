#!/usr/bin/python
#########################################
# Function:    check process status
# Usage:       python check_process.py ${process name}
# Author:      CMS DEV TEAM
# Company:     Aliyun Inc.
# Version:     1.1
#########################################

import os
import sys
import time
import httplib
import logging
import socket
import random
from subprocess import Popen, PIPE
from logging.handlers import RotatingFileHandler

logger = None
REMOTE_HOST = None
REMOTE_PORT = None
REMOTE_MONITOR_URI = None
UUID = None


def collector(process_name):
    cmd1 = "ps auxww | grep -v -e grep -e check_process.py -e sampler.py | grep -w \"%s\" | wc -l" % process_name
    p1 = Popen(cmd1, shell=True, stdout=PIPE)
    process_number = p1.communicate()[0].strip()
    print process_number
    timestamp = int(time.time() * 1000)
    process_name = process_name.replace(' ', '_')

    if UUID:
        content = 'vm.process.number ' + str(timestamp) + ' ' + process_number + ' ns=ACS/ECS unit=Count instanceId=%s processName=%s\n' % (UUID, process_name)
    else:
        content = 'vm.process.number ' + str(timestamp) + ' ' + process_number + ' ns=ACS/ECS unit=Count processName=%s\n' % process_name

    interval = random.randint(0, 5000)
    time.sleep(interval / 1000.0)

    headers = {"Content-Type": "text/plain", "Accept": "text/plain"}
    http_client = None
    exception = None
    try:
        try:
            http_client = httplib.HTTPConnection(REMOTE_HOST, REMOTE_PORT)
            http_client.request(method="POST", url=REMOTE_MONITOR_URI, body=content, headers=headers)
            response = http_client.getresponse()
            if response.status == 200:
                return
            else:
                logger.warn("response code %d" % response.status)
                logger.warn("response code %s" % response.read())
        except Exception, ex:
            exception = ex
    finally:
        if http_client:
            http_client.close()
        if exception:
            logger.error(exception)


if __name__ == '__main__':
    REMOTE_HOST = 'open.cms.aliyun.com'
    REMOTE_PORT = 80

    # get report address
    if not os.path.isfile("../cmscfg"):
        pass
    else:
        props = {}
        prop_file = file("../cmscfg", 'r')
        for line in prop_file.readlines():
            kv = line.split('=')
            props[kv[0].strip()] = kv[1].strip()
        prop_file.close()
        if props.get('report_domain'):
            REMOTE_HOST = props.get('report_domain')
        if props.get('report_port'):
            REMOTE_PORT = props.get('report_port')

    # get uuid
    if not os.path.isfile("../aegis_quartz/conf/uuid"):
        pass
    else:
        uuid_file = file("../aegis_quartz/conf/uuid", 'r')
        UUID = uuid_file.readline()
        UUID = UUID.lower()

    REMOTE_MONITOR_URI = "/metrics/putLines"
    LOG_FILE = "/tmp/check_process.log"
    LOG_LEVEL = logging.INFO
    LOG_FILE_MAX_BYTES = 1024 * 1024
    LOG_FILE_MAX_COUNT = 3
    logger = logging.getLogger('check_process')
    logger.setLevel(LOG_LEVEL)
    handler = RotatingFileHandler(filename=LOG_FILE, mode='a', maxBytes=LOG_FILE_MAX_BYTES,
                                  backupCount=LOG_FILE_MAX_COUNT)
    formatter = logging.Formatter(fmt='%(asctime)s - %(levelname)s - %(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    socket.setdefaulttimeout(10)
    try:
        collector(sys.argv[1])
    except Exception, e:
        logger.error(e)
        sys.exit(1)
