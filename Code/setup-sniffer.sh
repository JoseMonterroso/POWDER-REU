#!/bin/sh

set -x

SRC=`dirname $0`
. $SRC/setup-lib.sh

# Exit if we've already done this.
if [ -e $OURDIR/sniffer-done ]; then
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

maybe_install_packages virtualenv python-pip

cd demo-capsule/ospfv3_monitor
virtualenv -p /usr/bin/python2 env
. env/bin/activate
pip install -r requirements.txt
python main.py -vv --controller=${CONTROLLERNODE}-${MGMTLAN} --port=8080 --log-file=$OURDIR/sniffer.log &
deactivate

touch $OURDIR/sniffer-done

exit 0
