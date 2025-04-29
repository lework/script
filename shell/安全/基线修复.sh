# 密码复杂度
sed -i  -e 's|# minlen = 9|minlen = 9|g' -e 's|# minclass = 0|minclass = 3|g'  /etc/security/pwquality.conf

# ssh空闲
sed -i -e 's|#ClientAliveInterval 0|ClientAliveInterval 600|g' -e 's|#ClientAliveCountMax 3|ClientAliveCountMax 3|g'  /etc/ssh/sshd_config 

# 检查密码重用是否受限制
sed -i '/password    sufficient                                   pam_unix.so/ s/$/& remember=5/' /etc/pam.d/password-auth
sed -i '/password    sufficient                                   pam_unix.so/ s/$/& remember=5/' /etc/pam.d/system-auth