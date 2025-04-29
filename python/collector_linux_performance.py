#!/usr/bin/python
#########################################
# Function:    sample linux performance indices
# Usage:       python sampler.py
# Author:      CMS DEV TEAM
# Company:     Aliyun Inc.
# Version:     1.1
#########################################

import os
import os.path
import sys
import time
import operator
import httplib
import logging
import socket
import random
from shutil import copyfile
from subprocess import Popen, PIPE
from logging.handlers import RotatingFileHandler

logger = None
REMOTE_HOST = None
REMOTE_PORT = None
REMOTE_MONITOR_URI = None
UUID = None


def get_mem_usage_percent():
    try:
        f = open('/proc/meminfo', 'r')
        for line in f:
            if line.startswith('MemTotal:'):
                mem_total = int(line.split()[1])
            elif line.startswith('MemFree:'):
                mem_free = int(line.split()[1])
            elif line.startswith('Buffers:'):
                mem_buffer = int(line.split()[1])
            elif line.startswith('Cached:'):
                mem_cache = int(line.split()[1])
            elif line.startswith('SwapTotal:'):
                vmem_total = int(line.split()[1])
            elif line.startswith('SwapFree:'):
                vmem_free = int(line.split()[1])
            else:
                continue
        f.close()
    except:
        return None
    physical_percent = usage_percent(mem_total - (mem_free + mem_buffer + mem_cache), mem_total)
    virtual_percent = 0
    if vmem_total > 0:
        virtual_percent = usage_percent((vmem_total - vmem_free), vmem_total)
    return physical_percent, virtual_percent


black_list = ('iso9660',)


def usage_percent(use, total):
    try:
        ret = (float(use) / total) * 100
    except ZeroDivisionError:
        raise Exception("ERROR - zero division error")
    return ret


def get_disk_partition():
    return_list = []
    pd = []
    try:
        f = open("/proc/filesystems", "r")
        for line in f:
            if not line.startswith("nodev"):
                fs_type = line.strip()
                if fs_type not in black_list:
                    pd.append(fs_type)
        f.close()

        f = open('/etc/mtab', "r")
        for line in f:
            if line.startswith('none'):
                continue
            tmp = line.strip().split()
            ft = tmp[2]
            if ft not in pd:
                continue
            return_list.append(tmp[1])
        f.close()
    except:
        return None
    return return_list


def check_disk():
    try:
        return_dict = {}
        p_list = get_disk_partition()
        for i in p_list:
            dt = os.statvfs(i)
            use = (dt.f_blocks - dt.f_bfree) * dt.f_frsize #disk space has been used
            total = (dt.f_blocks - dt.f_bfree + dt.f_bavail) * dt.f_frsize #all space that can be used
            return_dict[i] = ('%.2f' % (usage_percent(use, total),), ('%.2f' % (total * 1.0 / (1024 * 1000000))))
    except:
        return None
    return return_dict


_CLOCK_TICKS = os.sysconf("SC_CLK_TCK")


def get_cpu_time():
    need_sleep = False
    if not os.path.isfile('/tmp/cpu_stat') or os.path.getsize('/tmp/cpu_stat') == 0:
        copyfile('/proc/stat', '/tmp/cpu_stat')
        need_sleep = True

    try:
        try:
            f1 = open('/tmp/cpu_stat', 'r')
            first_line = f1.readline()
            if not first_line.startswith('cpu'):
                raise Exception('error cpu_stat content')
            values1 = first_line.split()
            total_time1 = 0
            for i in values1[1:]:
                total_time1 += int(i)
            idle_time1 = int(values1[4])
            iowait_time1 = int(values1[5])
        except Exception, e:
            copyfile('/proc/stat', '/tmp/cpu_stat')
            return None
    finally:
        f1.close()

    if need_sleep:
        time.sleep(1)

    f2 = open('/proc/stat', 'r')
    try:
        values2 = f2.readline().split()
        total_time2 = 0
        for i in values2[1:]:
            total_time2 += int(i)
        idle_time2 = int(values2[4])
        iowait_time2 = int(values2[5])
    finally:
        f2.close()
    idle_time = idle_time2 - idle_time1
    iowait_time = iowait_time2 - iowait_time1
    total_time = total_time2 - total_time1

    cpu_percentage = int(100.0 * (total_time - idle_time - iowait_time) / total_time)
    # compensate logic
    if total_time < 0 or idle_time < 0 or iowait_time < 0 or cpu_percentage < 0 or cpu_percentage > 100:
        time.sleep(1)
        f3 = open('/proc/stat', 'r')
        try:
            values3 = f3.readline().split()
            total_time3 = 0
            for i in values3[1:]:
                total_time3 += int(i)
            idle_time3 = int(values3[4])
            iowait_time3 = int(values3[5])
        finally:
            f3.close()
        idle_time = idle_time3 - idle_time2
        iowait_time = iowait_time3 - iowait_time2
        total_time = total_time3 - total_time2
        cpu_percentage = int(100.0 * (total_time - idle_time - iowait_time) / total_time)

    copyfile('/proc/stat', '/tmp/cpu_stat')
    return cpu_percentage


def network_io_kbitps():
    """Return network I/O statistics for every network interface
    installed on the system as a dict of raw tuples.
    """

    need_sleep = False
    if not os.path.isfile('/tmp/netio_stat') or os.path.getsize('/tmp/netio_stat') == 0:
        copyfile('/proc/net/dev', '/tmp/netio_stat')
        need_sleep = True

    try:
        try:
            start = int(os.path.getmtime("/tmp/netio_stat")) #seconds
            f1 = open("/tmp/netio_stat", "r")
            lines1 = f1.readlines()
            first_line = lines1[0]
            if not first_line.startswith('Inter-'):
                raise Exception('error netio_stat content')
            retdict1 = {}
            for line1 in lines1[2:]:
                colon1 = line1.find(':')
                name1 = line1[:colon1].strip()
                fields1 = line1[colon1 + 1:].strip().split()
                bytes_recv1 = float(fields1[0]) * 0.0078125
                bytes_sent1 = float(fields1[8]) * 0.0078125
                retdict1[name1] = (bytes_recv1, bytes_sent1)
        except Exception, e:
            logger.error(e)
            copyfile('/proc/net/dev', '/tmp/netio_stat')
            return None
    finally:
        f1.close()

    #first time run, need sleep 1 second
    if need_sleep:
        time.sleep(1)
    try:
        end = int(round(time.time())) # seconds

        f2 = open("/proc/net/dev", "r")
        lines2 = f2.readlines()
        retdict2 = {}
        for line2 in lines2[2:]:
            colon2 = line2.find(':')
            name2 = line2[:colon2].strip()
            fields2 = line2[colon2 + 1:].strip().split()
            bytes_recv2 = float(fields2[0]) * 0.0078125
            bytes_sent2 = float(fields2[8]) * 0.0078125
            retdict2[name2] = (bytes_recv2, bytes_sent2)
        retdict = merge_with(retdict2, retdict1)
        copyfile('/proc/net/dev', '/tmp/netio_stat')

        for k,v in retdict.iteritems():
            retdict[k] = tuple((x/(end-start)) for x in v)
        return retdict
    finally:
        f2.close()

def disk_io_Kbps():
    iostat = Popen("/usr/bin/iostat -d -k 1 2 | sed '/Device\|Linux\|^$/d' > /tmp/disk_io", shell=True, stdout=PIPE, stderr=PIPE)
    iostat_error = iostat.communicate()[1].strip()
    if iostat_error:
        logger.error("iostat not exists, %s" % iostat_error)
        return None

    retdict = {}
    exception = None
    try:
        try:
            f = open('/tmp/disk_io', 'r')
        except Exception, ex:
            exception = ex
            logger.error(exception)
        if exception:
            return None
        lines = f.readlines()
        for line in lines:
            name, _, readkps, writekps, _, _, = line.split()
            if name:
                readkps = float(readkps)
                writekps = float(writekps)
                retdict[name] = (readkps, writekps)
        return retdict
    finally:
        f.close()

def merge_with(d1, d2, fn=lambda x, y: tuple(map(operator.sub, x, y))):
    res = d1.copy() # "= dict(d1)" for lists of tuples
    for key, val in d2.iteritems(): # ".. in d2" for lists of tuples
        try:
            res[key] = fn(res[key], val)
        except KeyError:
            res[key] = val
    return res

def cal(x,y,z):
    return (y - x) / z

def get_load():
    try:
        f = open('/proc/loadavg', 'r')
        tmp = f.readline().split()
        lavg_1 = float(tmp[0])
        lavg_5 = float(tmp[1])
        lavg_15 = float(tmp[2])
        f.close()
    except:
        return None
    return lavg_1, lavg_5, lavg_15


def get_tcp_status():
    check_cmd = "command -v ss"
    check_proc = Popen(check_cmd, shell=True, stdout=PIPE)
    ss = check_proc.communicate()[0].rstrip('\n')
    if ss:
        cmd = "ss -ant | awk '{if(NR != 1) print $1}' | awk '{state=$1;arr[state]++} END{for(i in arr){printf \"%s=%s \", i,arr[i]}}' | sed 's/-/_/g' | sed 's/ESTAB=/ESTABLISHED=/g' | sed 's/FIN_WAIT_/FIN_WAIT/g'"
    else:
        cmd = "netstat -anp | grep tcp | awk '{print $6}' | awk '{state=$1;arr[state]++} END{for(i in arr){printf \"%s=%s \", i,arr[i]}}' | tail -n 1"
    tcp_proc = Popen(cmd, shell=True, stdout=PIPE)
    tcp_status = tcp_proc.communicate()[0].rstrip('\n')
    return tcp_status


def get_proc_number():
    cmd = "ps axu | wc -l | tail -n 1"
    proc_func = Popen(cmd, shell=True, stdout=PIPE)
    proc_number = proc_func.communicate()[0].rstrip('\n')
    return proc_number


def all_index():
    return (
        int(time.time() * 1000),
        get_cpu_time(),
        get_mem_usage_percent(),
        check_disk(),
        disk_io_Kbps(),
        network_io_kbitps(),
        get_load(),
        get_tcp_status(),
        get_proc_number()
    )


def collector():
    timestamp, cpu, mem, disk, disk_io, net, load, tcp_status, process_number = all_index()
    memory_utilization = ''
    cpu_utilization = ''
    disk_utilization = ''
    disk_io_read = ''
    disk_io_write = ''
    internet_networkrx = ''
    internet_networktx = ''
    tcp_status_count = ''
    process_count=''
    period_1 = ''
    period_5 = ''
    period_15 = ''

    if UUID:
        memory_utilization = 'vm.MemoryUtilization ' + str(timestamp) + ' ' + str(mem[0]) + ' ns=ACS/ECS unit=Percent instanceId=%s\n' % UUID

        if cpu is not None:
            cpu_utilization = 'vm.CPUUtilization ' + str(timestamp) + ' ' + str(cpu) + ' ns=ACS/ECS unit=Percent instanceId=%s\n' % UUID

        if load:
            period_1 = 'vm.LoadAverage ' + str(timestamp) + ' ' + str(load[0]) + ' ns=ACS/ECS unit=count' + ' instanceId=%s period=1min\n' % UUID
            period_5 = 'vm.LoadAverage ' + str(timestamp) + ' ' + str(load[1]) + ' ns=ACS/ECS unit=count' + ' instanceId=%s period=5min\n' % UUID
            period_15 = 'vm.LoadAverage ' + str(timestamp) + ' ' + str(load[2]) + ' ns=ACS/ECS unit=count' + ' instanceId=%s period=15min\n' % UUID

        if disk:
            for name, value in disk.items():
                disk_utilization = disk_utilization + 'vm.DiskUtilization ' + str(timestamp) + ' ' + str(value[0]) + ' ns=ACS/ECS unit=Percent instanceId=%s mountpoint=%s\n' % (UUID, name)

        if disk_io:
            for name, value in disk_io.items():
                disk_io_read = disk_io_read + 'vm.DiskIORead ' + str(timestamp) + ' ' + str(value[0]) + ' ns=ACS/ECS unit=Kilobytes/Second instanceId=%s diskname=%s\n' % (UUID, name)
                disk_io_write = disk_io_write + 'vm.DiskIOWrite ' + str(timestamp) + ' ' + str(value[1]) + ' ns=ACS/ECS unit=Kilobytes/Second instanceId=%s diskname=%s\n' % (UUID, name)
        if net:
            for name, value in net.items():
                internet_networkrx = internet_networkrx + 'vm.InternetNetworkRX ' + str(timestamp) + ' %.4f ns=ACS/ECS unit=Kilobits/Second instanceId=%s netname=%s\n' % (value[0], UUID, name)
                internet_networktx = internet_networktx + 'vm.InternetNetworkTX ' + str(timestamp) + ' %.4f ns=ACS/ECS unit=Kilobits/Second instanceId=%s netname=%s\n' % (value[1], UUID, name)

        if tcp_status:
            status_count = tcp_status.split()
            for element in status_count:
                key_value = element.split('=')
                tcp_status_count = tcp_status_count + 'vm.TcpCount ' + str(timestamp) + ' ' + key_value[1] + ' ns=ACS/ECS unit=Count instanceId=%s state=%s\n' % (UUID, key_value[0])

        process_count = 'vm.ProcessCount ' + str(timestamp) + ' ' + process_number + ' ns=ACS/ECS unit=Count instanceId=%s\n' % UUID

    else:
        memory_utilization = 'vm.MemoryUtilization ' + str(timestamp) + ' ' + str(mem[0]) + ' ns=ACS/ECS unit=Percent\n'

        if cpu is not None:
            cpu_utilization = 'vm.CPUUtilization ' + str(timestamp) + ' ' + str(cpu) + ' ns=ACS/ECS unit=Percent\n'

        if load:
            period_1 = 'vm.LoadAverage ' + str(timestamp) + ' ' + str(load[0]) + ' ns=ACS/ECS unit=count period=1min\n'
            period_5 = 'vm.LoadAverage ' + str(timestamp) + ' ' + str(load[1]) + ' ns=ACS/ECS unit=count period=5min\n'
            period_15 = 'vm.LoadAverage ' + str(timestamp) + ' ' + str(load[2]) + ' ns=ACS/ECS unit=count period=15min\n'

        if disk:
            for name, value in disk.items():
                disk_utilization = disk_utilization + 'vm.DiskUtilization ' + str(timestamp) + ' ' + str(value[0]) + ' ns=ACS/ECS unit=Percent mountpoint=%s\n' % name

        if disk_io:
            for name, value in disk_io.items():
                disk_io_read = disk_io_read + 'vm.DiskIORead ' + str(timestamp) + ' ' + str(value[0]) + ' ns=ACS/ECS unit=Kilobytes/Second diskname=%s\n' % name
                disk_io_write = disk_io_write + 'vm.DiskIOWrite ' + str(timestamp) + ' ' + str(value[1]) + ' ns=ACS/ECS unit=Kilobytes/Second diskname=%s\n' % name
        if net:
            for name, value in net.items():
                internet_networkrx = internet_networkrx + 'vm.InternetNetworkRX ' + str(timestamp) + ' %.4f ns=ACS/ECS unit=Kilobits/Second netname=%s\n' % (value[0], name)
                internet_networktx = internet_networktx + 'vm.InternetNetworkTX ' + str(timestamp) + ' %.4f ns=ACS/ECS unit=Kilobits/Second netname=%s\n' % (value[1], name)

        if tcp_status:
            status_count = tcp_status.split()
            for element in status_count:
                key_value = element.split('=')
                tcp_status_count = tcp_status_count + 'vm.TcpCount ' + str(timestamp) + ' ' + key_value[1] + ' ns=ACS/ECS unit=Count state=%s\n' % key_value[0]

        process_count = 'vm.ProcessCount ' + str(timestamp) + ' ' + process_number + ' ns=ACS/ECS unit=Count\n'

    data_post = cpu_utilization + memory_utilization + period_1 + period_5 + period_15 + disk_utilization + disk_io_read + disk_io_write + internet_networkrx + internet_networktx + tcp_status_count + process_count
    print data_post
    interval = random.randint(0, 5000)
    time.sleep(interval / 1000.0)

    headers = {"Content-Type": "text/plain", "Accept": "text/plain"}
    exception = None
    http_client = None
    try:
        try:
            http_client = httplib.HTTPConnection(REMOTE_HOST, REMOTE_PORT)
            http_client.request(method="POST", url=REMOTE_MONITOR_URI, body=data_post, headers=headers)
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
    MONITOR_DATA_FILE_DIR = "/tmp"
    LOG_FILE = "/tmp/" + "vm.log"
    LOG_LEVEL = logging.INFO
    LOG_FILE_MAX_BYTES = 1024 * 1024
    LOG_FILE_MAX_COUNT = 3
    logger = logging.getLogger('sampler')
    logger.setLevel(LOG_LEVEL)
    handler = RotatingFileHandler(filename=LOG_FILE, mode='a', maxBytes=LOG_FILE_MAX_BYTES,
                                  backupCount=LOG_FILE_MAX_COUNT)
    formatter = logging.Formatter(fmt='%(asctime)s - %(levelname)s - %(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    socket.setdefaulttimeout(10)

    try:
        collector()
    except Exception, e:
        logger.error(e)
        sys.exit(1)
