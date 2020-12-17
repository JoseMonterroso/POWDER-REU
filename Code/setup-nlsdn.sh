#!/bin/sh

set -x

SRC=`dirname $0`
. $SRC/setup-lib.sh

# Exit if we've already done this.
if [ -e /etc/systemd/system/nlsdn.service ]; then
    exit 0
fi

cd $OURDIR

maybe_install_packages python-flask python-setuptools

git clone https://gitlab.flux.utah.edu/safeedge/pyroute2
cd pyroute2
python setup.py install
cd ..

git clone https://gitlab.flux.utah.edu/safeedge/nlsdn
cd nlsdn
python setup.py install
cd ..

# Do some post-install stuff.
mkdir -p /etc/nlsdn/certs
chmod 700 /etc/nlsdn/certs
cp -p nlsdn/etc/config.json /etc/nlsdn/
chown root:root /etc/nlsdn/config.json
chmod 660 /etc/nlsdn/config.json
cp -p nlsdn/tests/certs/* /etc/nlsdn/certs/
chmod 600 /etc/nlsdn/certs/*.key
cp -p nlsdn/etc/nlsdn.service /etc/systemd/system
mkdir -p /var/lib/nlsdn

# Fire it off!
systemctl daemon-reload
systemctl enable nlsdn
systemctl restart nlsdn

exit 0
