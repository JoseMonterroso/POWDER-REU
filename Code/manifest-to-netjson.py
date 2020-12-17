#!/usr/bin/env python2

import sys
import lxml.etree
import argparse
import os
import pwd
import json

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-l","--login",default=pwd.getpwuid(os.getuid()).pw_name,
        action='store_true')
    parser.add_argument(
        "-m","--mgmt-network",default="")
    parser.add_argument(
        "-L","--no-links",default=False,action='store_true')
    parser.add_argument("manifest",type=argparse.FileType('r'))
    return parser.parse_args()

def main():
    args = parse_args()

    ifref_node_map = {}
    iface_link_map = {}
    link_members = {}
    node_ifaces = {}
    allifaces = {}
    node_labels = {}

    contents = args.manifest.read()
    args.manifest.close()
    root = lxml.etree.fromstring(contents)

    mynickname = ""
    f = open("/var/emulab/boot/nickname","r")
    mynickname = f.read().rstrip("\r\n")
    eidpiddom = ".".join(mynickname.split(".")[1:])
    f.close()
    mydomain = ""
    f = open("/var/emulab/boot/mydomain","r")
    mydomain = f.read().rstrip("\r\n")
    f.close()
    expdomain = "%s.%s" % (eidpiddom,mydomain)

    # Find all the links:
    for elm in root.getchildren():
        if not elm.tag.endswith("}link"):
            continue
        name = elm.get("client_id")
        ifacerefs = []
        for elm2 in elm.getchildren():
            if elm2.tag.endswith("}interface_ref"):
                ifacename = elm2.get("client_id")
                ifacerefs.append(ifacename)
        for ifacename in ifacerefs:
            iface_link_map[ifacename] = name
        link_members[name] = ifacerefs

    # Find all the node interfaces and labels
    for elm in root.getchildren():
        if not elm.tag.endswith("}node"):
            continue
        name = elm.get("client_id")
        ifaces = {}
        labels = []
        for elm2 in elm.getchildren():
            if elm2.tag.endswith("}interface"):
                ifacename = elm2.get("client_id")
                ifaces[ifacename] = {}
                for elm3 in elm2.getchildren():
                    if not elm3.tag.endswith("}ip"):
                        continue
                    at = elm3.get("type")
                    if not (at == "ipv4" or at == "ipv6"):
                        continue
                    addrtuple = (
                        elm2.get("mac_address"),elm3.get("address"),
                        elm3.get("netmask"),elm3.get("prefixlen"))
                    ifaces[ifacename][at] = addrtuple
                    ifref_node_map[ifacename] = name
            elif elm2.tag.endswith("}label"):
                labels.append(elm2.get("name"))
        for (k,v) in ifaces.iteritems():
            allifaces[k] = v
        node_labels[name] = labels
        if ifaces:
            node_ifaces[name] = ifaces

    # Handle management network specially.
    node_mgmt_ips = {}
    if not args.mgmt_network:
        # Login to each node; find control net
        for (node,ifaces) in node_ifaces.items():
            f = os.popen("ssh -tt -o StrictHostKeyChecking=no -l %s %s.%s cat /var/emulab/boot/myip"
                         % (args.login,node,expdomain))
            ip = f.read().rstrip("\r\n")
            f.close()
            node_mgmt_ips[node] = ip
    else:
        # Find the interface for each node on the given args.mgmt_network
        if not args.mgmt_network in link_members:
            raise Exception("no such mgmt_network '%s'; aborting"
                            % (args.mgmt_network))
        for ifref in link_members[args.mgmt_network]:
            node = ifref_node_map[ifref]
            node_mgmt_ips[node] = node_ifaces[node][ifref]["ipv4"][1]

    # Collect interface names for each mac_address in the addrtuples
    mac_iface_map = {}
    for (node,ifaces) in node_ifaces.items():
        if not ifaces:
            continue
        f = os.popen("ssh -tt -o StrictHostKeyChecking=no -l %s %s.%s ip -br link show" % (args.login,node,expdomain))
        lines = f.read().split("\r\n")
        for l in lines:
            la = l.split()
            if len(la) != 4:
                continue
            (iface,mac) = (la[0],la[2].replace(":","").lower())
            mac_iface_map[mac] = iface
        f.close()

    # Construct the netjson dict
    nodes = []
    for (node,ifaces) in node_ifaces.items():
        intd = dict()
        for (iface,addrd) in ifaces.items():
            if not "ipv6" in addrd:
                continue
            (mac,ip,netmask,prefixlen) = addrd["ipv6"]
            intd[mac_iface_map[mac]] = "%s/%s" % (ip,prefixlen)
        nd = dict(
            id=node_mgmt_ips[node],
            properties={
                "interfaces":intd,
                "management-ip":node_mgmt_ips[node],
                "roles":node_labels[node],
            },
            label=node)
        nodes.append(nd)

    links = []
    if not args.no_links:
        for (link,members) in link_members.items():
            # skip mgmt network
            if args.mgmt_network and link == args.mgmt_network:
                continue
            if len(members) != 2:
                continue
            (s,t) = (members[0],members[1])
            (sn,tn) = (ifref_node_map[s],ifref_node_map[t])
            (smac,sip,snm,splen) = node_ifaces[sn][s]["ipv6"]
            (tmac,tip,tnm,tplen) = node_ifaces[tn][t]["ipv6"]
            ld = dict(source=sip,target=tip,cost="1",properties=dict(netmask=snm))
            links.append(ld)
                    
    output = dict(
        type="NetworkGraph",protocol="static",version=None,revision=None,
        metric=None,nodes=nodes,links=links)

    print json.dumps(output)

    exit(0)

if __name__ == "__main__":
    main()
