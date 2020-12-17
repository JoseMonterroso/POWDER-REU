#!/bin/sh

for pref in `ip -6 rule | grep -vE 'local|main' | grep lookup | cut -d: -f1` ; do
    ip -6 rule del pref $pref
    ip -6 route flush table $pref
done

systemctl stop nlsdn
rm -f /var/lib/nlsdn/db.json
systemctl start nlsdn
