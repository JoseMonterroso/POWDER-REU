#!/bin/sh

set -x

if [ -z "$EUID" ]; then
    EUID=`id -u`
fi
if [ $EUID -ne 0 ] ; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

export SRC=`dirname $0`
cd $SRC
. $SRC/setup-lib.sh

# We use setup-root-ssh.sh as a barrier, but it does let us disable
# global root pubkeys if we want to roll our own.
ALLNODE_SCRIPTS="setup-root-ssh.sh"
FRR_SCRIPTS=""
if [ "$DOFRR" = "1" ]; then
    FRR_SCRIPTS="setup-frr.sh"
fi
NLSDN_SCRIPTS=""
if [ "$DOIPV6" = "1" ]; then
    NLSDN_SCRIPTS="setup-nlsdn.sh setup-ipv6.py setup-nlsdn-bind-iface.py"
fi
if [ "$DONETFLOW" = "1" ]; then
    NETFLOW_SCRIPTS="setup-netflow.sh"
fi
if [ "$DOSNIFFERS" = "1" ]; then
    SNIFFER_SCRIPTS="setup-sniffer.sh"
fi
if [ "$DOSDN" = "1" ]; then
    CONTROLLER_SCRIPTS="setup-silk.sh setup-webapp.sh setup-orchestrator.sh setup-sdn.sh setup-critical-reroute.sh"
fi

# Don't run setup.sh twice
if [ -f $OURDIR/setup-done ]; then
    echo "setup already ran; not running again"
    exit 0
fi

# Some things we run everywhere.
for script in $ALLNODE_SCRIPTS ; do
    $SRC/$script 2>&1 | tee $OURDIR/${script}.log
done

# Install nlsdn everywhere
for script in $NLSDN_SCRIPTS ; do
    $SRC/$script 2>&1 | tee $OURDIR/${script}.log
done

# Install frr everywhere
for script in $FRR_SCRIPTS ; do
    $SRC/$script 2>&1 | tee $OURDIR/${script}.log
done

# Install netflow node stuff if necessary
if [ "$NETFLOW" = "1" ]; then
    for script in $NETFLOW_SCRIPTS ; do
	$SRC/$script 2>&1 | tee $OURDIR/${script}.log
    done
fi

# Install sniffer node stuff if necessary
if [ "$SNIFFER" = "1" ]; then
    for script in $SNIFFER_SCRIPTS ; do
	$SRC/$script 2>&1 | tee $OURDIR/${script}.log
    done
fi

# Install controller node stuff if necessary
if [ "$CONTROLLER" = "1" ]; then
    for script in $CONTROLLER_SCRIPTS ; do
	$SRC/$script 2>&1 | tee $OURDIR/${script}.log
    done
fi

exit 0
