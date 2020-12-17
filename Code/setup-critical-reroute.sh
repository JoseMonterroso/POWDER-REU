#!/bin/sh

set -x

SRC=`dirname $0`
. $SRC/setup-lib.sh

# Exit if we've already done this.
if [ -e $OURDIR/cr-done ]; then
    exit 0
fi

cd $OURDIR

if [ ! -e $OURDIR/Critical-Reroute ]; then
    git clone https://gitlab.flux.utah.edu/sredman/Critical-Reroute
fi

cd $OURDIR/Critical-Reroute

virtualenv -p /usr/bin/python2 env2
source env2/bin/activate
wget https://tools.netsa.cert.org/releases/netsa-python-1.5.tar.gz
tar -xvf netsa-python-1.5.tar.gz
pushd netsa-python-1.5 && ./setup.py install && popd
pip install -r requirements2.txt
deactivate

virtualenv --python python3 env
source env/bin/activate
pip install git+https://github.com/openwisp/netdiff@master
pip install git+https://gitlab.flux.utah.edu/safeedge/nlsdn@master
pip install git+https://gitlab.flux.utah.edu/safeedge/pyroute2@safeedge
pip install -r requirements.txt
deactivate

touch $OURDIR/cr-done

exit 0
