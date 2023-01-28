mkdir /etc/supervisord.d/scripts

cat <<EOF > /etc/supervisord.d/healthCheck.ini
[program:healthCheck]
command=/etc/supervisord.d/scripts/supervisor_healthCheck.py
process_name=%(program_name)s
numprocs=1
directory=/etc/supervisord.d/scripts/
autostart=true
startsecs=2
startretries=5
autorestart=true
stopsignal=TERM
stopwaitsecs=3
stopasgroup=true
killasgroup=true
user=root
redirect_stderr=true
stdout_logfile=/var/log/supervisor/healthCheck.log
stdout_logfile_maxbytes=200MB
stdout_logfile_backups=10
EOF