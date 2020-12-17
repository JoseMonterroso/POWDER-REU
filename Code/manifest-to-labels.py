#!/usr/bin/env python2

import sys
import lxml.etree
import socket

f = open(sys.argv[1],'r')
contents = f.read()
f.close()
root = lxml.etree.fromstring(contents)

hostname = socket.gethostname().lower()

# Find our node and dump any labels:
labels = {}
ours = False
for elm in root.getchildren():
    if not elm.tag.endswith("}node"):
        continue
    labels = {}
    for elm2 in elm.getchildren():
        if elm2.tag.endswith("}host") and elm2.get("name").lower() == hostname:
            ours = True
            break
        elif elm2.tag.endswith("}label"):
            labels[elm2.get("name")] = elm2.text
    if ours:
        break

if ours:
    for (k,v) in labels.iteritems():
        print "%s=%s" % (k.upper(),v)
    sys.exit(0)
else:
    sys.exit(1)
