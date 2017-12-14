#
# Yandex ClickHouse DBMS build script for RHEL based distributions
#
# Important notes:
#  - build requires ~35 GB of disk space
#  - each build thread requires 2 GB of RAM - for example, if you
#    have dual-core CPU with 4 threads you need 8 GB of RAM
#  - build user needs to have priviledges, preferrably with NOPASSWD
#
# Tested on:
#  - GosLinux IC4
#  - CentOS 6.8
#  - CentOS 7.2
#
# Copyright (C) 2016, 2017 Red Soft LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

# Git version of ClickHouse that we package
CH_VERSION="${CH_VERSION:-1.1.54318}"

# Git tag marker (stable/testing)
#CH_TAG="${CH_TAG:-testing}"
CH_TAG="${CH_TAG:-stable}"

# SSH username used to publish built packages
REPO_USER="${REPO_USER:-clickhouse}"

# Hostname of the server used to publish packages
REPO_SERVER="${REPO_SERVER:-10.81.1.162}"

# Root directory for repositories on the remote server
REPO_ROOT="${REPO_ROOT:-/var/www/html/repos/clickhouse}"

# Detect number of threads
export THREADS=$(grep -c ^processor /proc/cpuinfo)

# Build most libraries using default GCC
export PATH=${PATH/"/usr/local/bin:"/}:/usr/local/bin

# Determine RHEL major version
RHEL_VERSION=`rpm -qa --queryformat '%{VERSION}\n' '(redhat|sl|slf|centos|oraclelinux|goslinux)-release(|-server|-workstation|-client|-computenode)'`

function prepare_dependencies {

if [ ! -d lib ]; then
  mkdir lib
fi

#rm -rf lib/*

cd lib

# Install development packages
yum -y install rpm-build redhat-rpm-config gcc-c++ readline-devel\
  unixODBC-devel subversion python-devel git wget openssl-devel m4 createrepo\
  libicu-devel zlib-devel libtool-ltdl-devel

# Install MySQL client library from Oracle
if ! rpm --query mysql57-community-release; then
  yum -y --nogpgcheck install http://dev.mysql.com/get/mysql57-community-release-el$RHEL_VERSION-9.noarch.rpm
fi
yum -y install mysql-community-devel
if [ ! -e /usr/lib64/libmysqlclient.a ]; then
  ln -s /usr/lib64/mysql/libmysqlclient.a /usr/lib64/libmysqlclient.a
fi

# Install cmake
wget https://cmake.org/files/v3.9/cmake-3.9.3.tar.gz
tar xf cmake-3.9.3.tar.gz
cd cmake-3.9.3
./configure
make -j $THREADS
make install
cd ..

# Install GCC 7
wget http://mirror.linux-ia64.org/gnu/gcc/releases/gcc-7.2.0/gcc-7.2.0.tar.gz
tar zxf gcc-7.2.0.tar.gz
cd gcc-7.2.0
./contrib/download_prerequisites
cd ..
mkdir gcc-build
cd gcc-build
../gcc-7.2.0/configure --enable-languages=c,c++ --enable-linker-build-id --with-default-libstdcxx-abi=gcc4-compatible --disable-multilib
make -j $THREADS
make install
hash gcc g++
gcc --version
ln -f -s /usr/local/bin/gcc /usr/local/bin/gcc-7
ln -f -s /usr/local/bin/g++ /usr/local/bin/g++-7
ln -f -s /usr/local/bin/gcc /usr/local/bin/cc
ln -f -s /usr/local/bin/g++ /usr/local/bin/c++
cd ..

# Use GCC 7 for builds
export CC=gcc-7
export CXX=g++-7

# Install Boost
wget http://downloads.sourceforge.net/project/boost/boost/1.65.1/boost_1_65_1.tar.bz2
tar xf boost_1_65_1.tar.bz2
cd boost_1_65_1
./bootstrap.sh
./b2 --toolset=gcc-7 -j $THREADS
PATH=$PATH ./b2 install --toolset=gcc-7 -j $THREADS
cd ..

# Clang requires Python27
rpm -ivh http://dl.iuscommunity.org/pub/ius/stable/Redhat/6/x86_64/epel-release-6-5.noarch.rpm
rpm -ivh http://dl.iuscommunity.org/pub/ius/stable/Redhat/6/x86_64/ius-release-1.0-14.ius.el6.noarch.rpm
yum clean all
yum install python27

# Install Clang from Subversion repo
mkdir llvm
cd llvm
svn co http://llvm.org/svn/llvm-project/llvm/tags/RELEASE_500/final llvm
cd llvm/tools
svn co http://llvm.org/svn/llvm-project/cfe/tags/RELEASE_500/final clang
cd ../projects/
svn co http://llvm.org/svn/llvm-project/compiler-rt/tags/RELEASE_500/final compiler-rt
cd ../..
mkdir build
cd build/
cmake -D CMAKE_BUILD_TYPE:STRING=Release ../llvm -DCMAKE_CXX_LINK_FLAGS="-Wl,-rpath,/usr/local/lib64 -L/usr/local/lib64"
make -j $THREADS
make install
hash clang
cd ../../..

}

function make_packages {

# Clean up after previous run
rm -f ~/rpmbuild/RPMS/x86_64/clickhouse*
rm -f ~/rpmbuild/SRPMS/clickhouse*
rm -f rpm/*.zip
rm -rf /tmp/ClickHouse-*

# Configure RPM build environment
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
echo '%_topdir %(echo $HOME)/rpmbuild
%_smp_mflags  -j'"$THREADS" > ~/.rpmmacros

# Create RPM packages
cd rpm
sed -e s/@CH_VERSION@/$CH_VERSION/ -e s/@CH_TAG@/$CH_TAG/ clickhouse.spec.in > clickhouse.spec
#wget -O ~/rpmbuild/SOURCES/ClickHouse-$CH_VERSION-$CH_TAG.zip https://github.com/yandex/ClickHouse/archive/v$CH_VERSION-$CH_TAG.zip
git clone --recursive --branch v1.1.54318-stable https://github.com/yandex/ClickHouse /tmp/ClickHouse-$CH_VERSION-$CH_TAG
cd /tmp/ClickHouse-$CH_VERSION-$CH_TAG
git submodule update --init --recursive
cd /tmp/
zip -r ~/rpmbuild/SOURCES/ClickHouse-$CH_VERSION-$CH_TAG.zip ClickHouse-$CH_VERSION-$CH_TAG
cd /root/clickhouse-rpm/rpm/

rpmbuild -bs clickhouse.spec
CC=gcc-7 CXX=g++-7 rpmbuild -bb clickhouse.spec

}

function publish_packages {
  if [ ! -d /tmp/clickhouse-repo ]; then
    mkdir /tmp/clickhouse-repo
  fi
  rm -rf /tmp/clickhouse-repo/*
  cp ~/rpmbuild/RPMS/x86_64/clickhouse*.rpm /tmp/clickhouse-repo
  createrepo /tmp/clickhouse-repo

  scp -B -r /tmp/clickhouse-repo $REPO_USER@$REPO_SERVER:/tmp/clickhouse-repo
  ssh $REPO_USER@$REPO_SERVER "rm -rf $REPO_ROOT/$CH_TAG/el$RHEL_VERSION && mv /tmp/clickhouse-repo $REPO_ROOT/$CH_TAG/el$RHEL_VERSION"
}

if [[ "$1" != "publish_only"  && "$1" != "build_only" ]]; then
  prepare_dependencies
fi
if [ "$1" != "publish_only" ]; then
  make_packages
fi
if [ "$1" == "publish_only" ]; then
  publish_packages
fi