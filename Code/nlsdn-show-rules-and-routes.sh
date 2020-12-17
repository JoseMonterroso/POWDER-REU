#!/bin/sh

#
# Make a nasty "translation table" script and run the output of ip -6
# rule and ip -6 route through it.  It assumes we are the only ipv6
# tenants on this host, and assumes a 1-to-1 mapping between rule pref
# and table num... which is what nlsdn does by default.  It's very
# stupid and wasteful... but it's sh!
#

REGEXFILE=/tmp/ipv6-hosts-translator.regex
PREFIX=2620:7c:d000:ffff

touch $REGEXFILE
truncate -s 0 $REGEXFILE

IFS='
'

for addr in `grep :: /etc/hosts | cut -f1` ; do
    hostent=`getent hosts $addr`
    if [ -z "$hostent" ] ; then
        continue
    fi
    # We want the ipv6 addr from getent; it's minimal-formatted, like
    # what we'll see out of the `ip` tool.  So that's what we want to
    # apply our regex to.
    addr=`echo "$hostent" | awk '{print $1}'`
    host=`echo "$hostent" | awk '{print $2}'`
    echo "s/$addr \\([^(]\\)/$addr ($host) \\\\1/g" >> $REGEXFILE
done

for rule in `ip -6 rule | grep -vE 'local|main' | grep lookup` ; do
    pref=`echo $rule | cut -d: -f1`
    for regex in `cat $REGEXFILE` ; do
        if [ -z "$regex" ]; then
            continue
        fi
        rule=`echo $rule | sed -e "$regex"`
    done
    rule=`echo "$rule" | sed -e "s/$PREFIX//g"`
    echo $rule
    for route in `ip -6 route show table $pref` ; do
        for regex in `cat $REGEXFILE` ; do
            if [ -z "$regex" ]; then
                continue
            fi
            route=`echo $route | sed -e "$regex"`
        done
        route=`echo "$route" | sed -e "s/$PREFIX//g"`
        echo "TABENT: $route"
    done
done

exit 0
