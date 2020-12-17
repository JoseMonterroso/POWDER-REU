#!/bin/sh

DIRNAME=`dirname $0`

OURDIR=/root/setup
SRC=/local/repository
SETTINGS=$OURDIR/settings
LOCALSETTINGS=$OURDIR/settings.local
TOPOMAP=$OURDIR/topomap
BOOTDIR=/var/emulab/boot
TMCC=/usr/local/etc/emulab/tmcc

# Various default values
MGMTLAN="mgmt-lan"
DOAPTUPDATE=1
INCLUDE_VHOSTS=0

# Setup time logging stuff early
TIMELOGFILE=$OURDIR/setup-time.log
FIRSTTIME=0
if [ ! -f $OURDIR/setup-lib-first ]; then
    touch $OURDIR/setup-lib-first
    FIRSTTIME=`date +%s`
fi

logtstart() {
    area=$1
    varea=`echo $area | sed -e 's/[^a-zA-Z_0-9]/_/g'`
    stamp=`date +%s`
    date=`date`
    eval "LOGTIMESTART_$varea=$stamp"
    echo "START $area $stamp $date" >> $TIMELOGFILE
}

logtend() {
    area=$1
    #varea=${area//-/_}
    varea=`echo $area | sed -e 's/[^a-zA-Z_0-9]/_/g'`
    stamp=`date +%s`
    date=`date`
    eval "tss=\$LOGTIMESTART_$varea"
    tsres=`expr $stamp - $tss`
    resmin=`perl -e 'print '"$tsres"' / 60.0 . "\n"'`
    echo "END $area $stamp $date" >> $TIMELOGFILE
    echo "TOTAL $area $tsres $resmin" >> $TIMELOGFILE
}

if [ $FIRSTTIME -ne 0 ]; then
    logtstart "libfirsttime"
fi

[ -e $OURDIR ] || mkdir -p $OURDIR
[ -e $SETTINGS ] || touch $SETTINGS
[ -e $LOCALSETTINGS ] || touch $LOCALSETTINGS
cd $OURDIR


LOCKFILE="lockfile-create --retry 65535 "
RMLOCKFILE="lockfile-remove "
PSWDGEN="openssl rand -hex 10"
SSH="ssh -o StrictHostKeyChecking=no"
SCP="scp -p -o StrictHostKeyChecking=no"

# Setup apt-get to not prompt us
if [ ! -e /etc/dpkg/dpkg.cfg.d/cloudlab ]; then
    echo "force-confdef" > /etc/dpkg/dpkg.cfg.d/cloudlab
    echo "force-confold" >> /etc/dpkg/dpkg.cfg.d/cloudlab
fi
export DEBIAN_FRONTEND=noninteractive
# -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" 
DPKGOPTS=''
APTGETINSTALLOPTS='-y'
APTGETINSTALL="apt-get $DPKGOPTS install $APTGETINSTALLOPTS"
DO_APT_UPGRADE=0

#if [ ! -e $OURDIR/apt-updated ]; then
#    apt-get -y update
#fi
export NCPUS=`grep processor /proc/cpuinfo | wc -l`

do_apt_update() {
    if [ ! -f $OURDIR/apt-updated -a "${DOAPTUPDATE}" = "1" ]; then
	apt-get update
	touch $OURDIR/apt-updated
    fi
}

are_packages_installed() {
    retval=1
    while [ ! -z "$1" ] ; do
	dpkg -s "$1" >/dev/null 2>&1
	if [ ! $? -eq 0 ] ; then
	    retval=0
	fi
	shift
    done
    return $retval
}

maybe_install_packages() {
    if [ ! ${DO_APT_UPGRADE} -eq 0 ] ; then
        # Just do an install/upgrade to make sure the package(s) are installed
	# and upgraded; we want to try to upgrade the package.
	$APTGETINSTALL $@
	return $?
    else
	# Ok, check if the package is installed; if it is, don't install.
	# Otherwise, install (and maybe upgrade, due to dependency side effects).
	# Also, optimize so that we try to install or not install all the
	# packages at once if none are installed.
	are_packages_installed $@
	if [ $? -eq 1 ]; then
	    return 0
	fi

	retval=0
	while [ ! -z "$1" ] ; do
	    are_packages_installed $1
	    if [ $? -eq 0 ]; then
		$APTGETINSTALL $1
		retval=`expr $retval \| $?`
	    fi
	    shift
	done
	return $retval
    fi
}

##
## Grab our geni creds, and create a GENI credential cert
##
are_packages_installed python python-cryptography
success=`expr $? = 1`
# Keep trying again with updated cache forever;
# we must have this package.
while [ ! $success -eq 0 ]; do
    do_apt_update
    apt-get $DPKGOPTS install $APTGETINSTALLOPTS python python-cryptography
    success=$?
done

if [ ! -e $OURDIR/geni.key ]; then
    geni-get key > $OURDIR/geni.key
    cat $OURDIR/geni.key | grep -q END\ .\*\PRIVATE\ KEY
    if [ ! $? -eq 0 ]; then
	echo "ERROR: could not get geni key; aborting!"
	exit 1
    fi
fi
if [ ! -e $OURDIR/geni.certificate ]; then
    geni-get certificate > $OURDIR/geni.certificate
    cat $OURDIR/geni.certificate | grep -q END\ CERTIFICATE
    if [ ! $? -eq 0 ]; then
	echo "ERROR: could not get geni cert; aborting!"
	exit 1
    fi
fi

if [ ! -e /root/.ssl/encrypted.pem ]; then
    mkdir -p /root/.ssl
    chmod 600 /root/.ssl

    cat $OURDIR/geni.key > /root/.ssl/encrypted.pem
    cat $OURDIR/geni.certificate >> /root/.ssl/encrypted.pem
fi

if [ ! -e $OURDIR/manifests.xml ]; then
    python $DIRNAME/getmanifests.py $OURDIR/manifests
    if [ ! $? -eq 0 ]; then
	# Fall back to geni-get
	echo "WARNING: falling back to getting manifest from AM, not Portal -- multi-site experiments will not work fully!"
	geni-get manifest > $OURDIR/manifests.0.xml
    fi
fi

if [ ! -e $OURDIR/encrypted_admin_pass ]; then
    cat /root/setup/manifests.0.xml | perl -e '@lines = <STDIN>; $all = join("",@lines); if ($all =~ /^.+<[^:]+:password[^>]*>([^<]+)<\/[^:]+:password>.+/igs) { print $1; }' > $OURDIR/encrypted_admin_pass
fi

if [ ! -e $OURDIR/decrypted_admin_pass -a -s $OURDIR/encrypted_admin_pass ]; then
    openssl smime -decrypt -inform PEM -inkey geni.key -in $OURDIR/encrypted_admin_pass -out $OURDIR/decrypted_admin_pass
fi

#
# Suck in user parameters, if we haven't already.  This also pulls in
# global labels.
#
if [ ! -e $OURDIR/parameters ]; then
    python2 $DIRNAME/manifest-to-parameters.py $OURDIR/manifests.0.xml > $OURDIR/parameters
fi
. $OURDIR/parameters

#
# Figure out which cluster we're in, our role; etc.
#
if [ ! -f $OURDIR/labels ]; then
    python2 $DIRNAME/manifest-to-labels.py $OURDIR/manifests.0.xml > $OURDIR/labels
fi
. $OURDIR/labels

#
# Figure out which nodes/lans in our cluster are in which roles.
#
if [ ! -f $OURDIR/groupvars ]; then
    python2 $DIRNAME/manifest-to-groupvars.py $OURDIR/manifests.0.xml $CLUSTER > $OURDIR/groupvars
fi
. $OURDIR/groupvars

#
# Overwrite the params.
#
echo "ADMIN_PASS='${ADMIN_PASS}'" >> $OURDIR/parameters
echo "ADMIN_PASS_HASH='${ADMIN_PASS_HASH}'" >> $OURDIR/parameters

CREATOR=`cat $BOOTDIR/creator`
SWAPPER=`cat $BOOTDIR/swapper`
NODEID=`cat $BOOTDIR/nickname | cut -d . -f 1`
PNODEID=`cat $BOOTDIR/nodeid`
EEID=`cat $BOOTDIR/nickname | cut -d . -f 2`
EPID=`cat $BOOTDIR/nickname | cut -d . -f 3`
OURDOMAIN=`cat $BOOTDIR/mydomain`
NFQDN="`cat $BOOTDIR/nickname`.$OURDOMAIN"
PFQDN="`cat $BOOTDIR/nodeid`.$OURDOMAIN"
MYIP=`cat $BOOTDIR/myip`
EXTERNAL_NETWORK_INTERFACE=`cat $BOOTDIR/controlif`
HOSTNAME=`cat ${BOOTDIR}/nickname | cut -f1 -d.`
ARCH=`uname -m`
SWAPPER_EMAIL=`geni-get slice_email`
if [ -z "${SWAPPER_EMAIL}" ]; then
    SWAPPER_EMAIL="$SWAPPER@$OURDOMAIN"
fi

#
# Grab our topomap so we can see how many nodes we have.
# NB: only safe to use topomap for non-fqdn things.
#
if [ ! -f $TOPOMAP ]; then
    python2 $DIRNAME/manifest-to-topomap.py $OURDIR/manifests.0.xml > $TOPOMAP
    if [ ! $? -eq 0 ]; then
	echo "ERROR: could not extract topomap from manifest; aborting!"
	exit 1
    fi

    # Filter out blockstore nodes
    cat $TOPOMAP | grep -v '^bsnode,' > $TOPOMAP.no.bsnode
    mv $TOPOMAP.no.bsnode $TOPOMAP
    cat $TOPOMAP | grep -v '^bslink,' > $TOPOMAP.no.bslink
    mv $TOPOMAP.no.bslink $TOPOMAP
fi

#
# Create a map of node nickname to FQDN (and another one of pnode id to FQDN).
# This supports geni multi-site experiments.
#
if [ \( -s $OURDIR/manifests.xml \) -a \( ! \( -s $OURDIR/fqdn.map \) \) ]; then
    cat manifests.xml | tr -d '\n' | sed -e 's/<node /\n<node /g'  | sed -n -e "s/^<node [^>]*client_id=['\"]*\([^'\"]*\)['\"].*<host name=['\"]\([^'\"]*\)['\"].*$/\1\t\2/p" > $OURDIR/fqdn.map
    # Add a newline if we wrote anything.
    if [ -s $OURDIR/fqdn.map ]; then
	echo '' >> $OURDIR/fqdn.map
    fi
    # Filter out any blockstore nodes
    # XXX: this strategy doesn't work, because only the NM node makes
    # the fqdn.map file.  So, just look for bsnode for now.
    #BSNODES=`cat /var/emulab/boot/tmcc/storageconfig | sed -n -e 's/^.* HOSTID=\([^ \t]*\) .*$/\1/p' | xargs`
    #for bs in $BSNODES ; do
    #	cat $OURDIR/fqdn.map | grep -v "^${bs}"$'\t' > $OURDIR/fqdn.map.tmp
    #	mv $OURDIR/fqdn.map.tmp $OURDIR/fqdn.map
    #done
    if [ $INCLUDE_VHOSTS -eq 0 ]; then
	cat $OURDIR/fqdn.map | grep -v '^vhost' > $OURDIR/fqdn.map.tmp
	mv $OURDIR/fqdn.map.tmp $OURDIR/fqdn.map
    fi
    # XXX: why doesn't the tab grep work here, sigh...
    #cat $OURDIR/fqdn.map | grep -v '^bsnode'$'\t' > $OURDIR/fqdn.map.tmp
    cat $OURDIR/fqdn.map | grep -v '^bsnode' > $OURDIR/fqdn.map.tmp
    mv $OURDIR/fqdn.map.tmp $OURDIR/fqdn.map
    cat $OURDIR/fqdn.map | grep -v '^fw[ \t]*' > $OURDIR/fqdn.map.tmp
    mv $OURDIR/fqdn.map.tmp $OURDIR/fqdn.map
    cat $OURDIR/fqdn.map | grep -v '^fw-s2[ \t]*' > $OURDIR/fqdn.map.tmp
    mv $OURDIR/fqdn.map.tmp $OURDIR/fqdn.map

    cat manifests.xml | tr -d '\n' | sed -e 's/<node /\n<node /g'  | sed -n -e "s/^<node [^>]*component_id=['\"]*[a-zA-Z0-9:\+\.]*node+\([^'\"]*\)['\"].*<host name=['\"]\([^'\"]*\)['\"].*$/\1\t\2/p" > $OURDIR/fqdn.physical.map
    # Add a newline if we wrote anything.
    if [ -s $OURDIR/fqdn.physical.map ]; then
	echo '' >> $OURDIR/fqdn.physical.map
    fi
    # (Maybe) Filter out any vhost nodes
    if [ $INCLUDE_VHOSTS -eq 0 ]; then
	cat $OURDIR/fqdn.physical.map | grep -v '[ \t]vhost\.' > $OURDIR/fqdn.physical.map.tmp
    fi
    # Filter out any blockstore nodes
    cat $OURDIR/fqdn.physical.map | grep -v '[ \t]bsnode\.' > $OURDIR/fqdn.physical.map.tmp
    mv $OURDIR/fqdn.physical.map.tmp $OURDIR/fqdn.physical.map
    # Filter out any firewall nodes
    cat $OURDIR/fqdn.physical.map | grep -v '[ \t]*fw\.' > $OURDIR/fqdn.physical.map.tmp
    mv $OURDIR/fqdn.physical.map.tmp $OURDIR/fqdn.physical.map
    cat $OURDIR/fqdn.physical.map | grep -v '[ \t]*fw-s2\.' > $OURDIR/fqdn.physical.map.tmp
    mv $OURDIR/fqdn.physical.map.tmp $OURDIR/fqdn.physical.map

    # Create a parallel ssh/scp host list using FQDNs.
    awk '{print $2}' < $OURDIR/fqdn.map > $OURDIR/pssh.hosts
fi

if [ ! -s $OURDIR/fqdn.map ]; then
    echo "ERROR: failed to create fqdn.map; aborting!"
    exit 1
fi

#
# Grab our list of short-name and FQDN nodes.  One way or the other, we have
# an fqdn map.  First we tried the GENI way; then the old Emulab way with
# topomap.
#
ALLNODES=`cat $OURDIR/fqdn.map | cut -f1 | xargs`
ALLFQDNS=`cat $OURDIR/fqdn.map | cut -f2 | xargs`

##
## If we have no package cache, or if we're supposed to do an update,
## force an update.  This is the last thing we do.
##
if [ "${DOAPTUPDATE}" = "1" -o `ls -1 /var/lib/apt/lists/*_Packages | wc -l` = 0 ]; then
    do_apt_update
fi

##
## Util functions.
##

getfqdn() {
    n=$1
    fqdn=`cat $OURDIR/fqdn.map | grep -E "$n\s" | cut -f2`
    echo $fqdn
}

service_enable() {
    service=$1
    if [ ${HAVE_SYSTEMD} -eq 0 ]; then
	update-rc.d $service enable
    else
	systemctl enable $service
    fi
}

service_disable() {
    service=$1
    if [ ${HAVE_SYSTEMD} -eq 0 ]; then
	update-rc.d $service disable
    else
	systemctl disable $service
    fi
}

service_restart() {
    service=$1
    if [ ${HAVE_SYSTEMD} -eq 0 ]; then
	service $service restart
    else
	systemctl restart $service
    fi
}

service_stop() {
    service=$1
    if [ ${HAVE_SYSTEMD} -eq 0 ]; then
	service $service stop
    else
	systemctl stop $service
    fi
}

service_start() {
    service=$1
    if [ ${HAVE_SYSTEMD} -eq 0 ]; then
	service $service start
    else
	systemctl start $service
    fi
}

GETTER=`which wget`
if [ -n "$GETTER" ]; then
    GETTEROUT="$GETTER --remote-encoding=unix -c -O"
    GETTER="$GETTER --remote-encoding=unix -c -N"
    GETTERLOGARG="-o"
else
    GETTER="/bin/false NO WGET INSTALLED!"
    GETTEROUT="/bin/false NO WGET INSTALLED!"
fi

get_url() {
    if [ -z "$GETTER" ]; then
	/bin/false
	return
    fi

    urls="$1"
    outfile="$2"
    if [ -n "$3" ]; then
	retries=$3
    else
	retries=3
    fi
    if [ -n "$4" ]; then
	interval=$4
    else
	interval=5
    fi
    if [ -n "$5" ]; then
	force="$5"
    else
	force=0
    fi

    if [ -n "$outfile" -a -f "$outfile" -a $force -ne 0 ]; then
	rm -f "$outfile"
    fi

    success=0
    tmpfile=`mktemp /tmp/wget.log.XXX`
    for url in $urls ; do
	tries=$retries
	while [ $tries -gt 0 ]; do
	    if [ -n "$outfile" ]; then
		$GETTEROUT $outfile $GETTERLOGARG $tmpfile "$url"
	    else
		$GETTER $GETTERLOGARG $tmpfile "$url"
	    fi
	    if [ $? -eq 0 ]; then
		if [ -z "$outfile" ]; then
		    # This is the best way to figure out where wget
		    # saved a file!
		    outfile=`bash -c "cat $tmpfile | sed -n -e 's/^.*Saving to: '$'\u2018''\([^'$'\u2019'']*\)'$'\u2019''.*$/\1/p'"`
		    if [ -z "$outfile" ]; then
			outfile=`bash -c "cat $tmpfile | sed -n -e 's/^.*File '$'\u2018''\([^'$'\u2019'']*\)'$'\u2019'' not modified.*$/\1/p'"`
		    fi
		fi
		success=1
		break
	    else
		sleep $interval
		tries=`expr $tries - 1`
	    fi
	done
	if [ $success -eq 1 ]; then
	    break
	fi
    done

    rm -f $tmpfile

    if [ $success -eq 1 ]; then
	echo "$outfile"
	/bin/true
    else
	/bin/false
    fi
}

# Time logging
if [ $FIRSTTIME -ne 0 ]; then
    logtend "libfirsttime"
fi
