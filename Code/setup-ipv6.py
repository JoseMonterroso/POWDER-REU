#!/usr/bin/env python2

import os
import socket
from lxml import etree as ET

def findif(mac=None,ip=None):
    (output,thing) = (None,None)
    if mac:
        thing = mac.lower()
        if thing.find(":") == -1:
            thing = "%s:%s:%s:%s:%s:%s" % (
                mac[0:2],mac[2:4],mac[4:6],mac[6:8],mac[8:10],mac[10:])
        fd = os.popen("ip -br link")
        output = fd.read().splitlines()
        fd.close()
    elif ip:
        thing = ip
        fd = os.popen("ip -br addr")
        output = fd.read().splitlines()
        fd.close()
    else:
        return None
    for line in output:
        if thing in line:
            return line.split(' ')[0]
    return None

nsmap = {
    "g":"http://www.geni.net/resources/rspec/3",
    "c":"http://www.protogeni.net/resources/rspec/ext/johnsond/1"
}

hostname = socket.gethostname()
fd = os.popen("/usr/bin/geni-get manifest")
m = fd.read()
fd.close()

x = ET.fromstring(m)
node = None
for n in x.findall("g:node",namespaces=nsmap):
    host = n.find("g:host",namespaces=nsmap)
    if host is not None and host.get("name").lower() == hostname:
        node = n
        break
if node == None:
    raise Exception(
        "unable to find manifest node matching hostname '%s'" % (hostname))

print "Setting addresses for %s ..." % (hostname,)

addrs = {}
mgmtip = None
for i in node.findall("g:interface",namespaces=nsmap):
    dev = None
    mac = i.get("mac_address")
    if mac:
        dev = findif(mac=mac)
    if not dev:
        print "WARNING: could not find device for MAC %s, skipping!" % (mac,)
    for a in i.findall("g:ip",namespaces=nsmap):
        if a.get("type") == "ipv4" and i.get("client_id").endswith(":ifM"):
            mgmtip = a.get("address")
    for a in i.findall("c:ip",namespaces=nsmap):
        if a.get("type") != "ipv6":
            continue
        (addr,prefixlen) = (a.get("address"),a.get("prefixlen"))
        addrs[dev] = "%s/%s" % (addr,prefixlen)
        print "Will add %s/%s to %s (%s)" % (addr,prefixlen,dev,mac)
if True or len(addrs) > 1:
    print "Enabling overall ipv6 forwarding and segment routing..."
    os.system("sysctl -w net.ipv6.conf.all.forwarding=1")
    os.system("sysctl -w net.ipv6.conf.all.seg6_enabled=1")
    for dev in addrs.keys():
        print "Enabling segment routing for %s ..." % (dev,)
        os.system("sysctl -w net.ipv6.conf.%s.seg6_enabled=1" % (dev,))
        print "Enabling ipv6 forwarding for %s ..." % (dev,)
        os.system("sysctl -w net.ipv6.conf.%s.forwarding=1" % (dev,))
for dev in addrs.keys():
    print "Disabling ipv6 autoconf for %s ..." % (dev,)
    os.system("sysctl -w net.ipv6.conf.%s.autoconf=0" % (dev,))
    print "Flushing existing ipv6 addresses for %s ..." % (dev,)
    os.system("ip -6 addr flush dev %s" % (dev,))
    print "Downing interface %s to allow sysctls to take effect ..." % (dev,)
    os.system("ip link set %s down" % (dev,))
for (dev,a) in addrs.iteritems():
    print "Adding address %s to %s" % (a,dev)
    os.system("ip -6 addr add %s dev %s" % (a,dev))
    print "Bringing up interface %s  ..." % (dev,)
    os.system("ip link set %s up" % (dev,))

# Collect ipv6 addrs for /etc/hosts
hostslines = []
for n in x.findall("g:node",namespaces=nsmap):
    for i in n.findall("g:interface",namespaces=nsmap):
        for a in i.findall("c:ip",namespaces=nsmap):
            if a.get("type") != "ipv6":
                continue
            (addr,prefixlen) = (a.get("address"),a.get("prefixlen"))
            name = i.get("client_id").replace(':','-')
            hostslines.append("%s\t%s\n" % (addr,name))

print "Writing to /etc/hosts..."
fd = open("/etc/hosts","a")
for line in hostslines:
    fd.write(line)
fd.close()

print "Writing mgmt IP %s..." % (mgmtip,)
fd = open("/root/setup/mgmt-ip","w")
fd.write(mgmtip + "\n")
fd.close()

print "Writing interface IPs..."
fd = open("/root/setup/interfaces-ipv6","w")
for dev in addrs.keys():
    fd.write("%s,%s\n" % (dev,addrs[dev]))
fd.close()
