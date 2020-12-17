#!/bin/sh

set -x

SRC=`dirname $0`
. $SRC/setup-lib.sh

# Exit if we've already done this.
if [ -e $OURDIR/sdn-done ]; then
    exit 0
fi

cd $OURDIR

if [ ! -e $OURDIR/demo-capsule ]; then
    git clone https://gitlab.flux.utah.edu/safeedge/demo-capsule.git
    cd demo-capsule
    sed -i -e 's|url = git@gitlab.flux.utah.edu:|url = https://gitlab.flux.utah.edu/|' .gitmodules
    git submodule update --init --recursive
    cd ..
fi

maybe_install_packages crudini virtualenv python-pip python3

cd demo-capsule/segment-routing-sdn-controller
virtualenv -p /usr/bin/python3 env
. env/bin/activate
pip install git+https://gitlab.flux.utah.edu/safeedge/pyroute2@safeedge
pip install git+https://gitlab.flux.utah.edu/safeedge/nlsdn
pip install -r requirements.txt
crudini --set --existing params.conf DEFAULT net_json $OURDIR/netinfo.json
crudini --set --existing params.conf DEFAULT ovs_regex ".*${CONTROLLERNODE}.*"
$OURDIR/demo-capsule/segment-routing-sdn-controller/debug_ryu.py \
    --config-file=params.conf >$OURDIR/sdn-controller.log 2>&1 &
deactivate

touch $OURDIR/sdn-done

exit 0
