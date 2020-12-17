#!/bin/sh

set -x

SRC=`dirname $0`
. $SRC/setup-lib.sh

# Exit if we've already done this.
if [ -e $OURDIR/frr-done ]; then
    exit 0
fi

cd $OURDIR

curl -sL https://repos.emulab.net/emulab.key | apt-key add -
(. /etc/os-release && echo "deb https://repos.emulab.net/frr/${ID} ${UBUNTU_CODENAME} main" > /etc/apt/sources.list.d/frr.list)
apt-get -y update
maybe_install_packages frr frr-pythontools frr-snmp frr-rpki-rtrlib

if [ -f $OURDIR/mgmt-ip -a -f $OURDIR/interfaces-ipv6 ]; then
    MGMTIP=`cat $OURDIR/mgmt-ip`
    cat <<EOF >/etc/frr/zebra.conf
hostname $NODEID
password zebra
enable password zebra
log file /var/log/frr/zebra.log
ip forwarding
line vty

EOF
    while read line ; do
	iface=`echo $line | cut -d, -f1`
	addr=`echo $line | cut -d, -f2`
	echo "interface $iface" >> /etc/frr/zebra.conf
	echo "  ipv6 address $addr" >> /etc/frr/zebra.conf
    done < $OURDIR/interfaces-ipv6

    cat <<EOF >/etc/frr/ospf6d.conf
hostname $NODEID
password zebra
log file /var/log/frr/ospf6d.log
service advanced-vty

EOF
    while read line ; do
	iface=`echo $line | cut -d, -f1`
	addr=`echo $line | cut -d, -f2`
	if [ $NODEID = "node-cb" ] || [ $NODEID = "node-5" ] || [ $NODEID = "node-co" ] || [ $NODEID = "node-13" ]; then
		if [ $addr != "2620:7c:d000:ffff::5a/126" ] && [ $addr != "2620:7c:d000:ffff::59/126" ] && [ $addr != "2001:db8:a0b:12f0::65/126" ] && [ $addr != "2001:db8:a0b:12f0::66/126" ]; then
			echo "interface $iface" >> /etc/frr/ospf6d.conf
		fi
	else
		echo "interface $iface" >> /etc/frr/ospf6d.conf
	fi
    done < $OURDIR/interfaces-ipv6
    cat <<EOF >>/etc/frr/ospf6d.conf

router ospf6
  ospf6 router-id $MGMTIP
EOF
  if [ $NODEID = "node-cb" ] || [ $NODEID = "node-5" ] || [ $NODEID = "node-co" ] || [ $NODEID = "node-13" ]; then
    cat <<EOF >>/etc/frr/ospf6d.conf
  redistribute bgp
EOF
  fi

    while read line ; do
	iface=`echo $line | cut -d, -f1`
	addr=`echo $line | cut -d, -f2`
	if [ $NODEID = "node-cb" ] || [ $NODEID = "node-5" ] || [ $NODEID = "node-co" ] || [ $NODEID = "node-13" ]; then
		if [ $addr != "2620:7c:d000:ffff::5a/126" ] && [ $addr != "2620:7c:d000:ffff::59/126" ] && [ $addr != "2001:db8:a0b:12f0::65/126" ] && [ $addr != "2001:db8:a0b:12f0::66/126" ]; then
		  cat <<EOF >>/etc/frr/ospf6d.conf
  area 0.0.0.0 range $addr
  interface $iface area 0.0.0.0
EOF
		fi
	else
		cat <<EOF >>/etc/frr/ospf6d.conf
  area 0.0.0.0 range $addr
  interface $iface area 0.0.0.0
EOF
	fi
    done < $OURDIR/interfaces-ipv6

    if [ $NODEID = "node-cb" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
router bgp 1
 neighbor 2620:7c:d000:ffff::1 remote-as 1
 neighbor 2620:7c:d000:ffff::1d remote-as 1
 neighbor 2620:7c:d000:ffff::25 remote-as 1
 neighbor 2620:7c:d000:ffff::5a remote-as 2
 !
 address-family ipv6 unicast
  neighbor 2620:7c:d000:ffff::1 activate
  neighbor 2620:7c:d000:ffff::1d activate
  neighbor 2620:7c:d000:ffff::25 activate
  neighbor 2620:7c:d000:ffff::5a activate
 exit-address-family
EOF
    elif [ $NODEID = "node-8" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
router bgp 1
 neighbor 2620:7c:d000:ffff::d remote-as 1
 neighbor 2620:7c:d000:ffff::26 remote-as 1
 neighbor 2620:7c:d000:ffff::2a remote-as 1
 !
 address-family ipv6 unicast
  neighbor 2620:7c:d000:ffff::d activate
  neighbor 2620:7c:d000:ffff::26 activate
  neighbor 2620:7c:d000:ffff::2a activate
 exit-address-family
EOF

    elif [ $NODEID = "node-10" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
route-map SSR permit 10
 set large-community 1:10:5
exit
!
router bgp 1
 neighbor 2620:7c:d000:ffff::2 remote-as 1
 neighbor 2620:7c:d000:ffff::21 remote-as 1
 neighbor 2620:7c:d000:ffff::29 remote-as 1
 !
 address-family ipv6 unicast
  network 2620:7c:d000:ffff::50/126
  neighbor 2620:7c:d000:ffff::2 activate
  neighbor 2620:7c:d000:ffff::2 route-map SSR out
  neighbor 2620:7c:d000:ffff::21 activate
  neighbor 2620:7c:d000:ffff::21 route-map SSR out
  neighbor 2620:7c:d000:ffff::29 activate
  neighbor 2620:7c:d000:ffff::29 route-map SSR out
 exit-address-family
EOF

    elif [ $NODEID = "node-7" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
route-map SSR permit 10
 set large-community 1:2:1
!
router bgp 1
 neighbor 2620:7c:d000:ffff::e remote-as 1
 neighbor 2620:7c:d000:ffff::1e remote-as 1
 neighbor 2620:7c:d000:ffff::22 remote-as 1
 !
 address-family ipv6 unicast
  network 2620:7c:d000:ffff::54/126
  neighbor 2620:7c:d000:ffff::e activate
  neighbor 2620:7c:d000:ffff::e route-map SSR out
  neighbor 2620:7c:d000:ffff::1e activate
  neighbor 2620:7c:d000:ffff::1e route-map SSR out
  neighbor 2620:7c:d000:ffff::22 activate
  neighbor 2620:7c:d000:ffff::22 route-map SSR out
 exit-address-family
EOF

    elif [ $NODEID = "node-5" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
router bgp 2
 neighbor 2001:db8:a0b:12f0::12 remote-as 2
 neighbor 2001:db8:a0b:12f0::16 remote-as 2
 neighbor 2001:db8:a0b:12f0::1a remote-as 2
 neighbor 2620:7c:d000:ffff::59 remote-as 1
 !
 address-family ipv6 unicast
  network 2620:7c:d000:ffff::58/126
  neighbor 2001:db8:a0b:12f0::12 activate
  neighbor 2001:db8:a0b:12f0::16 activate
  neighbor 2001:db8:a0b:12f0::1a activate
  neighbor 2620:7c:d000:ffff::59 activate
 exit-address-family
EOF

    elif [ $NODEID = "node-11" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
route-map SSR permit 10
 set large-community 2:1:3
!
router bgp 2
 neighbor 2001:db8:a0b:12f0::15 remote-as 2
 neighbor 2001:db8:a0b:12f0::2e remote-as 2
 neighbor 2001:db8:a0b:12f0::3a remote-as 2
 !
 address-family ipv6 unicast
  network 2001:db8:a0b:12f0::4c/126
  neighbor 2001:db8:a0b:12f0::15 activate
  neighbor 2001:db8:a0b:12f0::15 route-map SSR out
  neighbor 2001:db8:a0b:12f0::2e activate
  neighbor 2001:db8:a0b:12f0::2e route-map SSR out
  neighbor 2001:db8:a0b:12f0::3a activate
  neighbor 2001:db8:a0b:12f0::3a route-map SSR out
 exit-address-family
EOF

    elif [ $NODEID = "node-12" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
route-map SSR permit 10
 set large-community 2:1:1
!
router bgp 2
 neighbor 2001:db8:a0b:12f0::19 remote-as 2
 neighbor 2001:db8:a0b:12f0::2d remote-as 2
 neighbor 2001:db8:a0b:12f0::3e remote-as 2
 !
 address-family ipv6 unicast
  network 2001:db8:a0b:12f0::60/126
  neighbor 2001:db8:a0b:12f0::19 activate
  neighbor 2001:db8:a0b:12f0::19 route-map SSR out
  neighbor 2001:db8:a0b:12f0::2d activate
  neighbor 2001:db8:a0b:12f0::2d route-map SSR out
  neighbor 2001:db8:a0b:12f0::3e activate
  neighbor 2001:db8:a0b:12f0::3e route-map SSR out
 exit-address-family
EOF

    elif [ $NODEID = "node-co" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
router bgp 2
 neighbor 2001:db8:a0b:12f0::11 remote-as 2
 neighbor 2001:db8:a0b:12f0::39 remote-as 2
 neighbor 2001:db8:a0b:12f0::3d remote-as 2
 neighbor 2001:db8:a0b:12f0::66 remote-as 3
 !
 address-family ipv6 unicast
  network 2001:db8:a0b:12f0::64/126
  neighbor 2001:db8:a0b:12f0::11 activate
  neighbor 2001:db8:a0b:12f0::39 activate
  neighbor 2001:db8:a0b:12f0::3d activate
  neighbor 2001:db8:a0b:12f0::66 activate
 exit-address-family
EOF

    elif [ $NODEID = "node-13" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
router bgp 3
 neighbor 2001:db8:a0b:12f0::65 remote-as 2
 neighbor 3000:63b:3ff:fdd2::6a remote-as 3
 neighbor 3000:63b:3ff:fdd2::6e remote-as 3
 neighbor 3000:63b:3ff:fdd2::72 remote-as 3
 !
 address-family ipv6 unicast
  neighbor 2001:db8:a0b:12f0::65 activate
  neighbor 3000:63b:3ff:fdd2::6a activate
  neighbor 3000:63b:3ff:fdd2::6e activate
  neighbor 3000:63b:3ff:fdd2::72 activate
 exit-address-family
EOF

    elif [ $NODEID = "node-14" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
router bgp 3
 neighbor 3000:63b:3ff:fdd2::69 remote-as 3
 neighbor 3000:63b:3ff:fdd2::7a remote-as 3
 neighbor 3000:63b:3ff:fdd2::7e remote-as 3
 !
 address-family ipv6 unicast
  neighbor 3000:63b:3ff:fdd2::69 activate
  neighbor 3000:63b:3ff:fdd2::7a activate
  neighbor 3000:63b:3ff:fdd2::7e activate
 exit-address-family
EOF

    elif [ $NODEID = "node-16" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
route-map SSR permit 10
 set large-community 3:4:4
!
router bgp 3
 neighbor 3000:63b:3ff:fdd2::71 remote-as 3
 neighbor 3000:63b:3ff:fdd2::7d remote-as 3
 neighbor 3000:63b:3ff:fdd2::86 remote-as 3
 !
 address-family ipv6 unicast
  network 3000:63b:3ff:fdd2::88/126
  neighbor 3000:63b:3ff:fdd2::71 activate
  neighbor 3000:63b:3ff:fdd2::71 route-map SSR out
  neighbor 3000:63b:3ff:fdd2::7d activate
  neighbor 3000:63b:3ff:fdd2::7d route-map SSR out
  neighbor 3000:63b:3ff:fdd2::86 activate
  neighbor 3000:63b:3ff:fdd2::86 route-map SSR out
 exit-address-family
EOF

    elif [ $NODEID = "node-17" ]; then
    cat <<EOF >/etc/frr/bgpd.conf
route-map SSR permit 10
 set large-community 3:1:1
!
router bgp 3
 neighbor 3000:63b:3ff:fdd2::6d remote-as 3
 neighbor 3000:63b:3ff:fdd2::79 remote-as 3
 neighbor 3000:63b:3ff:fdd2::85 remote-as 3
 !
 address-family ipv6 unicast
  network 3000:63b:3ff:fdd2::8c/126
  neighbor 3000:63b:3ff:fdd2::6d activate
  neighbor 3000:63b:3ff:fdd2::6d route-map SSR out
  neighbor 3000:63b:3ff:fdd2::79 activate
  neighbor 3000:63b:3ff:fdd2::79 route-map SSR out
  neighbor 3000:63b:3ff:fdd2::85 activate
  neighbor 3000:63b:3ff:fdd2::85 route-map SSR out
 exit-address-family
EOF
fi

    cat <<EOF >>/etc/frr/daemons

ospf6d=yes
bgpd=yes
EOF

fi

# Daemons look for this in preference to /etc/frr/${daemon}.conf,
# and it exists by default on Ubuntu, thus overrides everything.
# Make sure it does not exist before we run anything.
rm -f /etc/frr/frr.conf

systemctl enable frr
systemctl restart frr

touch $OURDIR/frr-done

exit 0
