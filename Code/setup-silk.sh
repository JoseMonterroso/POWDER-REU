#!/bin/sh

set -x

SRC=`dirname $0`
. $SRC/setup-lib.sh

# Exit if we've already done this.
if [ -e $OURDIR/silk-done ]; then
    exit 0
fi

cd $OURDIR

maybe_install_packages libglib2.0-dev

cd $OURDIR
wget https://tools.netsa.cert.org/releases/libfixbuf-2.3.0.tar.gz
tar -xzvf libfixbuf-2.3.0.tar.gz
mkdir libfixbuf-build && cd libfixbuf-build
../libfixbuf-2.3.0/configure && make -j$NCPUS && make install && ldconfig
cd ..

maybe_install_packages python3 python3-distutils libpython3-dev
wget https://tools.netsa.cert.org/releases/silk-3.18.1.tar.gz
tar -xzvf silk-3.18.1.tar.gz
mkdir silk-build && cd silk-build
../silk-3.18.1/configure --enable-ipv6 --with-python=/usr/bin/python3 --with-libfixbuf && make -j8 && make install && ldconfig
cd ..

touch $OURDIR/silk-done

exit 0
