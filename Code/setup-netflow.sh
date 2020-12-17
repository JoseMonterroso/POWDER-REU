#!/bin/sh

set -x

SRC=`dirname $0`
. $SRC/setup-lib.sh

# Exit if we've already done this.
modinfo ipt_NETFLOW >/dev/null 2>&1
if [ $? -eq 0 ]; then
    exit 0
fi

maybe_install_packages iptables-dev pkg-config snmpd libsnmp-dev dkms

cd $OURDIR
wget https://github.com/aabc/ipt-netflow/archive/v2.3.tar.gz
tar -xvf v2.3.tar.gz
cd ipt-netflow-2.3
./configure && make && sudo make all install
cd ..
echo dlmod netflow /usr/lib/snmp/dlmod/snmp_NETFLOW.so >> /etc/snmp/snmpd.conf
systemctl enable snmpd
systemctl restart snmpd

exit 0
