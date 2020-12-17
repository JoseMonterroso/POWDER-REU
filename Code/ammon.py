#!/usr/bin/env python

import geni.portal as portal
import geni.rspec.pg as RSpec
import geni.rspec.igext as IG
# Emulab specific extensions.
import geni.rspec.emulab as emulab
import geni.namespaces as GNS
from lxml import etree as ET
import random
import os.path
import sys
import struct
import socket

#
# For now, disable the testbed's root ssh key service until we can remove ours.
# It seems to race (rarely) with our startup scripts.
#
disableTestbedRootKeys = True

extns = "http://www.protogeni.net/resources/rspec/ext/johnsond/1"

class Label(RSpec.Resource):
    def __init__(self,name,value):
        self.name = name
        self.value = value

    def _write(self,root):
        el = ET.SubElement(root,"{%s}label" % (extns,))
        el.attrib["name"] = self.name
        el.text = self.value
        return el
RSpec.Node.EXTENSIONS.append(("Label",Label))
RSpec.Link.EXTENSIONS.append(("Label",Label))

def addInter(src,dst,pre6,pre4,postfix):
    iface = nodes[srcname].addInterface("%s%s" % (dst,postfix))
    sdnum = addrs["node-%s-%s%s" % (src,dst,postfix)]
    iface.addAddress(
        IPv4Address("%s.%s" % (pre4,str(sdnum)),prefixlen=bits4))
    iface.addAddress(
        IPv6Address("%s::%s" % (pre6,hex(sdnum)[2:]),prefixlen=bits6))
    link.addInterface(iface)

    iface = nodes[dstname].addInterface("%s%s" % (src,postfix))
    dsnum = addrs["node-%s-%s%s" % (dst,src,postfix)]
    iface.addAddress(
        IPv4Address("%s.%s" % (pre4,str(dsnum)),prefixlen=bits4))
    iface.addAddress(
        IPv6Address("%s::%s" % (pre6,hex(dsnum)[2:]),prefixlen=bits6))
    link.addInterface(iface)

def mask2prefixlen(x):
    bits = 32
    if isinstance(x,basestring):
        if x.find(":") > -1:
            (xh,xl) = struct.unpack('!QQ',socket.inet_pton(socket.AF_INET6,x))
            x = (xh << 64) | xl
            bits = 128
        else:
            (x,) = struct.unpack('!L',socket.inet_pton(socket.AF_INET,x))
    else:
        if x > 2**32:
            bits = 128
    ret = 0
    while bits > 0:
        if ret and (x & 1) == 0:
            raise Exception("invalid netmask")
        ret += x & 1
        x = x >> 1
        bits -= 1
    return ret

def prefixlen2mask(n,protocol=4):
    is6 = False
    if n > 32 or protocol == 6 or protocol == 'ipv6':
        sl = 128 - n
        is6 = True
    else:
        sl = 32 - n
    x = 0
    while n > 0:
        x <<= 1
        x |= 1
        n -= 1
    if sl > 0:
        x <<= sl
    if is6:
        enc = struct.pack('!QQ',x >> 64,x & (2**64 - 1))
        return socket.inet_ntop(socket.AF_INET6,enc)
    else:
        enc = struct.pack('!L',x)
        return socket.inet_ntop(socket.AF_INET,enc)
    return x

class IPv4Address(RSpec.Address):
    def __init__ (self, address, netmask=None, prefixlen=None):
        if netmask is None and prefixlen is None:
            raise Exception("no mask information")
        elif netmask:
            prefixlen = mask2prefixlen(netmask,protocol=4)
        else:
            netmask = prefixlen2mask(prefixlen,protocol=4)
        super(IPv4Address, self).__init__("ipv4")
        self.address = address
        self.netmask = netmask
        self.prefixlen = prefixlen

    def _write (self, element):
        ip = ET.SubElement(element, "{%s}ip" % (GNS.REQUEST.name))
        ip.attrib["address"] = self.address
        ip.attrib["netmask"] = self.netmask
        ip.attrib["prefixlen"] = str(self.prefixlen)
        ip.attrib["type"] = self.type
        return ip

class IPv6Address(RSpec.Address):
    def __init__ (self, address, netmask=None, prefixlen=None):
        if netmask is None and prefixlen is None:
            raise Exception("no mask information")
        elif netmask:
            prefixlen = mask2prefixlen(netmask,protocol=4)
        else:
            netmask = prefixlen2mask(prefixlen,protocol=4)
        super(IPv6Address, self).__init__("ipv6")
        self.address = address
        self.netmask = netmask
        self.prefixlen = prefixlen

    def _write (self, element):
        ip = ET.SubElement(element, "{%s}ip" % (extns,))
        ip.attrib["address"] = self.address
        ip.attrib["netmask"] = self.netmask
        ip.attrib["prefixlen"] = str(self.prefixlen)
        ip.attrib["type"] = self.type
        return ip

CMD = "sudo mkdir -p /root/setup && sudo -H /local/repository/setup.sh 2>&1 | sudo tee /root/setup/setup.log"

nodemap = {
    '7':1,'8':1,'10':1,'cb':1,'7se':1,'10se':1,#'2':1,
    '5':2,'12':2,'co':2,'12se':2,'11':2,'11se':2,#'9':2,
    '13':3,'16':3,'16se':3,'17':3,'17se':3,'14':3,#'15':3 # New Router Group
    }

mgmtmap = {
    '7':7,'8':8,'10':10,'cb':16,'7se':17,'10se':18,#'2':2,
    '5':5,'12':12,'co':15,'12se':21,'11':11,'11se':19,#'9':9,
    '13':22,'16':25,'16se':27,'17':26,'17se':28,'14':23,#'15':24 # New Router Group
    }

mgmtprefix = "10.60.0"
mgmtbits = 24
prefix4   = "192.168.0"   # AS1
prefix4_2 = "130.130.0"  # AS2
prefix4_3 = "200.200.0"  # AS3
bits4 = 30
prefix6   = "2620:7c:d000:ffff"    # AS1
prefix6_2 = "2001:db8:a0b:12f0"    # AS2
prefix6_3 = "3000:63b:3ff:fdd2"    # AS3
bits6 = 126
addrs = {
    #"node-2-cb":0x1,"node-2-7":0x5,"node-2-10":0x9,"node-2-8":0xd,
    "node-5-11":0x15,"node-5-12":0x19,"node-5-co":0x11, #"node-5-9":0x11,
    "node-5-cb-1":0x5a,
    "node-7-cb":0x1d,"node-7-10":0x21,"node-7-7se":0x56,"node-7-8":0xd, #"node-7-2":0x6,
    "node-8-cb":0x25,"node-8-10":0x29,"node-8-7":0xe, #"node-8-2":0xe,
    #"node-9-12":0x31,"node-9-11":0x2d,"node-9-5":0x12,"node-9-co":0x35,
    "node-10-8":0x2a,"node-10-7":0x22,"node-10-10se":0x52,"node-10-cb":0x1, #"node-10-2":0xa,
    "node-11-5":0x16,"node-11-co":0x39,"node-11-11se":0x4e,"node-11-12":0x2d, #"node-11-9":0x2e,
    "node-12-5":0x1a,"node-12-co":0x3d,"node-12-12se":0x61,"node-12-11":0x2e, #"node-12-9":0x32, # New Node 12
    "node-co-11":0x3a,"node-co-12":0x3e,"node-co-13":0x65,"node-co-5":0x12, #"node-co-9":0x36,  # New Node 13
    "node-cb-8":0x26,"node-cb-7":0x1e,"node-cb-10":0x2, #"node-cb-2":0x2,
    "node-cb-5-1":0x59,
    "node-7se-7":0x55,
    "node-10se-10":0x51,
    "node-11se-11":0x4d,
    "node-12se-12":0x62, # New 12 node
    "node-13-co":0x66,"node-13-16":0x71,"node-13-14":0x69,"node-13-17":0x6d, #"node-13-15":0x6d, # New Node Group
    "node-14-13":0x6a,"node-14-17":0x79,"node-14-16":0x7d,  #"node-14-15":0x75,
    #"node-15-13":0x6e,"node-15-16":0x7d,"node-15-14":0x76,"node-15-17":0x81,
    "node-16-13":0x72,"node-16-16se":0x89,"node-16-17":0x85,"node-16-14":0x7e,  #"node-16-15":0x7e,
    "node-17-16":0x86,"node-17-17se":0x8d,"node-17-14":0x7a,"node-17-13":0x6e, #"node-17-15":0x82,
    "node-16se-16":0x8a,
    "node-17se-17":0x8e
}

pc = portal.Context()

pc.defineParameter(
    "hostType","Physical Node Type",portal.ParameterType.NODETYPE,"d430",
    [("any","Any"),("d430","d430 (64GB)"),("d820","d820 (128GB)"),
     ("d740","d740 (96GB)"),("xl170","xl170 (64GB)"),("m510","m510 (64GB)")],
    longDescription="A specific hardware type to use for each physical node.  If you choose Any, the profile will allow Cloudlab to map the VMs to physical hosts using its resource mapper.  If you select a node type, you must ensure that type has enough memory to host 7 VMs with the amount of cores and memory in the next parameter, minus 4GB for the hypervisor.  (Cloudlab clusters all have machines of specific types.  When you set this field to a value that is a specific hardware type, you will only be able to instantiate this profile on clusters with machines of that type.  If unset, when you instantiate the profile, the resulting experiment may have machines of any available type allocated.)")
pc.defineParameter(
    "coresPerVM","Cores per VM",portal.ParameterType.INTEGER,1,
    longDescription="Number of cores each VM will get.")
pc.defineParameter(
    "ramPerVM","RAM per VM",portal.ParameterType.INTEGER,4096,
    longDescription="Amount of RAM each VM will get in MB.")
pc.defineParameter(
    "vmImage","VM Image",portal.ParameterType.STRING,
    'urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU18-64-STD',
    longDescription="The image your VMs will run.")
pc.defineParameter(
    "hostImage","Host Image",portal.ParameterType.STRING,
    'urn:publicid:IDN+emulab.net+image+emulab-ops//XEN49-64-STD',
    longDescription="The image your VM host nodes will run, if you specify a physical host node type above.")
pc.defineParameter(
    "linkSpeed","Experiment Link Speed",portal.ParameterType.INTEGER,0,
    [(0,"Any"),(1000000,"1Gb/s"),(10000000,"10Gb/s")],
    longDescription="A specific link speed to use for each node.  All experiment network interfaces will request this speed.")
pc.defineParameter(
    "linkLatency","LAN/Link Latency",portal.ParameterType.LATENCY,0,
    longDescription="A specific latency to use for each LAN and link.")
pc.defineParameter(
    "multiplex","Multiplex Networks",portal.ParameterType.BOOLEAN,True,
    longDescription="Multiplex all LANs and links.")
pc.defineParameter(
    "bestEffort","Best Effort Link Bandwidth",portal.ParameterType.BOOLEAN,True,
    longDescription="Do not require guaranteed bandwidth throughout switch fabric.")
pc.defineParameter(
    "trivialOk","Trivial Links Ok",portal.ParameterType.BOOLEAN,False,
    longDescription="Maybe use trivial links.")
pc.defineParameterGroup("safeedge","SafeEdge SDN Options")
pc.defineParameter(
    "doIPv6","Configure IPv6",portal.ParameterType.BOOLEAN,True,
    groupId="safeedge",
    longDescription="Configure IPv6 addresses and seg6 ipv6 settings as in the Ammon topology.")
pc.defineParameter(
    "doFRR","Enable FRR",portal.ParameterType.BOOLEAN,True,
    groupId="safeedge",
    longDescription="Configure and run Free Range Routing OSPFv6 on all nodes.")
pc.defineParameter(
    "doSDN","Enable SDN Controller Services",portal.ParameterType.BOOLEAN,True,
    groupId="safeedge",
    longDescription="Configure and enable SDN Controller services on the node in the controllerNode parameter.")
pc.defineParameter(
    "doSniffers","Enable OSPF Sniffers",portal.ParameterType.BOOLEAN,True,
    groupId="safeedge",
    longDescription="Configure and enable OSPFv6 sniffers on the nodes listed in the snifferNodes parameter.")
pc.defineParameter(
    "doNetflow","Enable Netflow Collectors",portal.ParameterType.BOOLEAN,True,
    groupId="safeedge",
    longDescription="Configure and enable netflow collectors on the nodes listed in the netflowNodes parameter.")
pc.defineParameter(
    "controllerNode","Controller Node",
    portal.ParameterType.STRING,"node-cb",groupId="safeedge")
pc.defineParameter(
    "netflowNodes","Netflow Collector Nodes",
    portal.ParameterType.STRING,"node-5 node-cb",groupId="safeedge")
pc.defineParameter(
    "snifferNodes","OSPF Sniffer Nodes",
    portal.ParameterType.STRING,"node-9 node-2",groupId="safeedge")

params = pc.bindParameters()

if params.coresPerVM < 1:
    pc.reportError(portal.ParameterError(
        "Must specify at least one core per VM",['coresPerVM']))
if params.ramPerVM < 1:
    pc.reportError(portal.ParameterError(
        "Must specify at least one core per VM",['ramPerVM']))
if not params.controllerNode:
    pc.reportError(portal.ParameterError(
        "Must specify exactly one node as the controller",['controllerNode']))
if not params.netflowNodes:
    pc.reportError(portal.ParameterError(
        "Must specify one or more nodes as netflow collectors",
        ['netflowNodes']))
if not params.snifferNodes:
    pc.reportError(portal.ParameterError(
        "Must specify one or more nodes as OSPF sniffers",
        ['snifferNodes']))
netflowNodes = params.netflowNodes.split(" ")
snifferNodes = params.snifferNodes.split(" ")

rspec = RSpec.Request()

tour = IG.Tour()
tour.Description(
    IG.Tour.TEXT,
    "Create an experiment emulating the Ammon/Entrypoint deployment, and do some SDN stuff via netlink, using the nlsdn application.")
rspec.addTour(tour)

vhosts = {}
nodes = {}
links = {}

mgmtlan = RSpec.LAN('mgmt-lan')
if params.multiplex:
    mgmtlan.link_multiplexing = True
    # Need this cause LAN() sets the link type to lan, not sure why.
    mgmtlan.type = "vlan"
if params.bestEffort:
    mgmtlan.best_effort = True
mgmtlan.trivial_ok = params.trivialOk

for (k,v) in addrs.iteritems():
    sa = k.split('-')[1:]
    (src,dst) = (sa[0],sa[1])
    if len(sa) > 2:
        linkidx = int(sa[2])
        postfix = "-" + sa[2]
    else:
        linkidx = None
        postfix = ""
    srcname = 'node-' + src
    dstname = 'node-' + dst
    for (name,num) in [(srcname,src),(dstname,dst)]:
        if name in nodes:
            continue
        vnode = nodes[name] = IG.XenVM(name)
        if disableTestbedRootKeys:
            vnode.installRootKeys(False, False)
        if name == params.controllerNode:
            vnode._ext_children.append(Label("controller","1"))
        if name in snifferNodes:
            vnode._ext_children.append(Label("sniffer","1"))
        if name in netflowNodes:
            vnode._ext_children.append(Label("netflow","1"))
        vnode.addService(RSpec.Execute(shell="sh",command=CMD))
        vnode.cores = params.coresPerVM
        vnode.ram = params.ramPerVM
        vnode.exclusive = True
        if params.vmImage:
            vnode.disk_image = params.vmImage
        if params.hostType != "any":
            vhostnum = nodemap[num]
            vhostname = "vhost%s" % (str(vhostnum),)
            vnode.InstantiateOn(vhostname)
            if not vhostname in vhosts:
                vhost = vhosts[vhostname] = RSpec.RawPC(vhostname)
                if disableTestbedRootKeys:
                    vhost.installRootKeys(False, False)
                vhost.exclusive = True
                if params.hostType:
                    vhost.hardware_type = params.hostType
                if params.hostImage:
                    vhost.disk_image = params.hostImage
        iface = vnode.addInterface("ifM")
        iface.addAddress(
          IPv4Address("%s.%s" % (mgmtprefix,mgmtmap[num]),prefixlen=mgmtbits))
        mgmtlan.addInterface(iface)
    linkname = "link-%s-%s%s" % (src,dst,postfix)
    revlinkname = "link-%s-%s%s" % (dst,src,postfix)
    if not linkname in links and not revlinkname in links:
        links[linkname] = link = RSpec.Link(linkname)
        if params.linkSpeed > 0:
            link.bandwidth = int(params.linkSpeed)
        if params.linkLatency > 0:
            link.latency = int(params.linkLatency)
        if params.multiplex:
            link.link_multiplexing = True
            link.type = "vlan"
        if params.bestEffort:
            link.best_effort = True
        mgmtlan.trivial_ok = params.trivialOk

        # AS Prefix Assignment
        if nodemap[src] == 1 and nodemap[dst] == 1:
            # AS1 Prefix
            addInter(src, dst, prefix6, prefix4, postfix)
        elif nodemap[src] == 2 and nodemap[dst] == 2:
            # AS2 Prefix
            addInter(src, dst, prefix6_2, prefix4_2, postfix)
        elif nodemap[src] == 3 and nodemap[dst] == 3:
            # AS3 Prefix
            addInter(src, dst, prefix6_3, prefix4_3, postfix)
        else:
            if (src == "cb" and dst == "5") or (src == "5" and dst == "cb"):
                # AS1-AS2 Connection Use AS1 Prefix
                addInter(src, dst, prefix6, prefix4, postfix)
            elif (src == "13" and dst == "co") or (src == "co" and dst == "13"):
                # AS2-AS3 Connection Use AS2 Prefix
                addInter(src, dst, prefix6_2, prefix4_2, postfix)

for vh in vhosts.keys():
    rspec.addResource(vhosts[vh])
for nn in nodes.keys():
    rspec.addResource(nodes[nn])
rspec.addResource(mgmtlan)
for ln in links.keys():
    rspec.addResource(links[ln])

pc.printRequestRSpec(rspec)
