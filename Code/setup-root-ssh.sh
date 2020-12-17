#!/bin/sh

##
## Setup a root ssh key on the calling node, and broadcast it to all the
## other nodes' authorized_keys file.
##

set -x

# Grab our libs
SRC=`dirname $0`
. "$SRC/setup-lib.sh"

if [ -e $OURDIR/root-ssh-done ]; then
    exit 0
fi

logtstart "root-ssh"

sshkeyscan() {
    #
    # Run ssh-keyscan on all nodes to build known_hosts.
    #
    ssh-keyscan $ALLNODES >> ~/.ssh/known_hosts
    chmod 600 ~/.ssh/known_hosts
    for node in $ALLNODES ; do
        fqdn=`getfqdn $node`
        publicip=`dig +noall +answer $fqdn A | sed -ne 's/^.*IN[ \t]*A[ \t]*\([0-9\.]*\)$/\1/p'`
        mgmtip=`getnodeip $node $MGMTLAN`
        echo "$publicip $fqdn,$publicip"
        echo "$mgmtip $node,$node-$MGMTLAN,$mgmtip"
    done | ssh-keyscan -4 -f - >> ~/.ssh/known_hosts
}

KEYNAME=id_rsa

# Remove it if it exists...
rm -f /root/.ssh/${KEYNAME} /root/.ssh/${KEYNAME}.pub

##
## Figure out our strategy.  Are we using the new geni_certificate and
## geni_key support to generate the same keypair on each host, or not.
##
geni-get key > $OURDIR/$KEYNAME
chmod 600 $OURDIR/${KEYNAME}
if [ -s $OURDIR/${KEYNAME} ] ; then
    ssh-keygen -f $OURDIR/${KEYNAME} -y > $OURDIR/${KEYNAME}.pub
    chmod 600 $OURDIR/${KEYNAME}.pub
    mkdir -p /root/.ssh
    chmod 600 /root/.ssh
    cp -p $OURDIR/${KEYNAME} $OURDIR/${KEYNAME}.pub /root/.ssh/
    ps axwww > $OURDIR/ps.txt
    cat $OURDIR/${KEYNAME}.pub >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    sshkeyscan
    logtend "root-ssh"
    exit 0
fi

##
## If geni calls are not available, make ourself a keypair; this gets copied
## to other roots' authorized_keys.
##
if [ ! -f /root/.ssh/${KEYNAME} ]; then
    ssh-keygen -t rsa -f /root/.ssh/${KEYNAME} -N ''
fi

if [ -f $SETTINGS ]; then
    . $SETTINGS
fi

SHAREDIR=/proj/$EPID/exp/$EEID
if [ -e $SHAREDIR ]; then
    SHAREKEYDIR=$SHAREDIR/tmp
    mkdir -p $SHAREKEYDIR

    cp /root/.ssh/${KEYNAME}.pub $SHAREKEYDIR/$HOSTNAME

    for node in $ALLNODES ; do
        while [ ! -f $SHAREKEYDIR/$node ]; do
            sleep 1
        done
        echo $node is up
        cat $SHAREKEYDIR/$node >> /root/.ssh/authorized_keys
    done
else
    for node in $ALLNODES ; do
        if [ "$node" != "$HOSTNAME" ]; then
            fqdn=`getfqdn $node`
            SUCCESS=1
            while [ $SUCCESS -ne 0 ]; do
                su -c "$SSH  -l $SWAPPER $fqdn sudo tee -a /root/.ssh/authorized_keys" $SWAPPER < /root/.ssh/${KEYNAME}.pub
                SUCCESS=$?
                sleep 1
            done
        fi
    done
fi

sshkeyscan

logtend "root-ssh"

exit 0
