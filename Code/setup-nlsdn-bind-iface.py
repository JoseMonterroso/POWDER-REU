#!/usr/bin/env python2

import os
import socket
import json
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
if not node:
    raise Exception(
        "unable to find manifest node matching hostname '%s'" % (hostname))

print "Setting addresses for %s ..." % (hostname,)

(ip,dev) = (None,None)
for i in node.findall("g:interface",namespaces=nsmap):
    if not i.get("client_id").endswith("ifM"):
        continue
    mac = i.get("mac_address")
    if not mac:
        continue
    dev = findif(mac=mac)
    if not dev:
        continue
    ip = None
    for a in i.findall("g:ip",namespaces=nsmap):
        if a.get("type") != "ipv4":
            continue
        ip = a.get("address")
        if ip:
            break
if ip:
    print "Moving nlsdn to listen on mgmt network %s (%s)..." % (ip,dev)
    fd = open('/etc/nlsdn/config.json','r+')
    blob = json.loads(fd.read())
    fd.seek(0)
    blob["server"]["host"] = ip
    fd.write(json.dumps(blob,sort_keys=True,indent=4))
    fd.close()
    print "Done."
else:
    print "Not moving nlsdn; could not find mgmt network!"
