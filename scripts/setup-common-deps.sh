#!/bin/bash
# Copyright (c) Facebook, Inc. and its affiliates.
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

set -efx -o pipefail
# Some of the packages must be build with the same compiler flags
# so that some low level types are the same size. Also, disable warnings.
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")

source $SCRIPTDIR/setup-helper-functions.sh

DEPENDENCY_DIR=${DEPENDENCY_DIR:-/tmp/velox-deps}
NPROC=$(getconf _NPROCESSORS_ONLN)

export CPU_TARGET=${CPU_TARGET:="avx"}
export CFLAGS=$(get_cxx_flags $CPU_TARGET)  # Used by LZO.
export CXXFLAGS=$CFLAGS  # Used by boost.
export CPPFLAGS=$CFLAGS  # Used by LZO.
export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig

FMT_VERSION=10.1.1
FB_OS_VERSION=v2024.02.26.00
BOOST_VERSION=boost-1.84.0
ARROW_VERSION=15.0.0


function install_fizz {
  if [ -f "/usr/local/lib/libfizz.a"  ]; then
    echo "fizz already installed"
    return 
  fi
  cd "${DEPENDENCY_DIR}"
  github_checkout facebookincubator/fizz "${FB_OS_VERSION}"
  cmake_install -DBUILD_TESTS=OFF -S fizz
}

function install_wangle {
  if [ -f "/usr/local/lib/libwangle.a"  ]; then
    echo "libwangle.a already installed"
    return 
  fi
  cd "${DEPENDENCY_DIR}"
  github_checkout facebook/wangle "${FB_OS_VERSION}"
  cmake_install -DBUILD_TESTS=OFF -S wangle
}

function install_mvfst {
  if [ -f "/usr/local/lib/libmvfst_client.a"  ]; then
    echo "mvst already installed"
    return 
  fi
  cd "${DEPENDENCY_DIR}"
  github_checkout facebook/mvfst "${FB_OS_VERSION}"
  cmake_install -DBUILD_TESTS=OFF
}

function install_fbthrift {
  if [ -f "/usr/local/include/thrift/lib/thrift/detail/protocol.h"  ]; then
    echo "fbthrift already installed"
    return 
  fi
  cd "${DEPENDENCY_DIR}"
  github_checkout facebook/fbthrift "${FB_OS_VERSION}"
  cmake_install -Denable_tests=OFF -DBUILD_TESTS=OFF -DBUILD_SHARED_LIBS=OFF
}

function install_arrow {
   if [ -f "/usr/local/include/arrow/ipc/api.h"  ]; then
    echo "arrow already installed"
    return 
  fi
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://archive.apache.org/dist/arrow/arrow-${ARROW_VERSION}/apache-arrow-${ARROW_VERSION}.tar.gz arrow
  (
    cd arrow/cpp
    cmake_install \
      -DARROW_PARQUET=OFF \
      -DARROW_WITH_THRIFT=ON \
      -DARROW_WITH_LZ4=ON \
      -DARROW_WITH_SNAPPY=ON \
      -DARROW_WITH_ZLIB=ON \
      -DARROW_WITH_ZSTD=ON \
      -DARROW_JEMALLOC=OFF \
      -DARROW_SIMD_LEVEL=NONE \
      -DARROW_RUNTIME_SIMD_LEVEL=NONE \
      -DARROW_WITH_UTF8PROC=OFF \
      -DARROW_TESTING=ON \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_BUILD_TYPE=Release \
      -DARROW_BUILD_STATIC=ON \
      -DThrift_SOURCE=BUNDLED

    # Install thrift.
    cd _build/thrift_ep-prefix/src/thrift_ep-build
    $SUDO cmake --install 
  )
}

function install_cuda {
  # See https://developer.nvidia.com/cuda-downloads
  if ! dpkg -l cuda-keyring 1>/dev/null; then
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
    $SUDO dpkg -i cuda-keyring_1.1-1_all.deb
    rm cuda-keyring_1.1-1_all.deb
    $SUDO apt update
  fi
  $SUDO apt install -y cuda-nvcc-$(echo $1 | tr '.' '-') cuda-cudart-dev-$(echo $1 | tr '.' '-')
}


function install_cmake {
  version=$(cmake --version | head -n 1 | cut -d' ' -f3 )
  if [ -n "$version" ] &&  [[ "3.28.3"  == "$version" ]]; then
    echo "cmake $version exists"
    return 
  fi
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://cmake.org/files/v3.28/cmake-3.28.3.tar.gz cmake-3
  cd cmake-3
  ./bootstrap --prefix=/usr/local
  make -j$(nproc)
  $SUDO make install
  cmake --version
}

function install_ninja {
  version=$(ninja --version)
  if [ -n "$version" ] &&  [[ "1.11.1"  == "$version" ]]; then
    echo "ninja $version exists"
    return 
  fi
  cd "${DEPENDENCY_DIR}"
  github_checkout ninja-build/ninja v1.11.1
  ./configure.py --bootstrap
  cmake -Bbuild-cmake
  cmake --build build-cmake
  $SUDO cp ninja /usr/local/bin/  
}

function install_folly {
  if [ -f "/usr/local/lib/libfolly.a"  ]; then
    echo "folly already installed"
    return 
  fi
  cd "${DEPENDENCY_DIR}"
  github_checkout facebook/folly "${FB_OS_VERSION}"
  cmake_install -DBUILD_TESTS=OFF -DFOLLY_HAVE_INT128_T=ON
}

function install_conda {
  arch=$(uname -m)
  cd "${DEPENDENCY_DIR}"
  conda_script="Miniconda3-latest-Linux-${arch}.sh"
  mkdir -p conda && cd conda
  if [ ! -f "${conda_script}" ]; then 
    wget https://repo.anaconda.com/miniconda/${conda_script}
  fi
  bash ${conda_script} -b -u
}

function install_openssl {
  if [ -f "/usr/local/include/openssl/bioerr.h" ]; then
    echo "Already installed!"
    return 
  fi
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://github.com/openssl/openssl/archive/refs/tags/OpenSSL_1_1_1s.tar.gz openssl
  cd openssl
  ./config no-shared
  make depend
  make
  $SUDO make install
}

function install_gflags {
  if [ -f "/usr/local/lib64/libgflags.a"  ]; then
    echo "Already installed!"
    return 
  fi
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://github.com/gflags/gflags/archive/v2.2.2.tar.gz gflags
  cd gflags
  cmake_install -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=ON -DBUILD_gflags_LIB=ON -DLIB_SUFFIX=64 -DCMAKE_INSTALL_PREFIX:PATH=/usr/local
}

function install_glog {
  if [ -f "/usr/local/include/glog/logging.h" ]; then
    echo "Already installed!"
    return 
  fi
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://github.com/google/glog/archive/v0.5.0.tar.gz glog
  cd glog
  cmake_install -DBUILD_STATIC_LIBS=ON -DCMAKE_INSTALL_PREFIX:PATH=/usr/local  
}

function install_snappy {
  if [ -f "/usr/local/include/snappy.h" ]; then
    echo "Already installed!"
    return 
  fi 
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://github.com/google/snappy/archive/1.1.8.tar.gz snappy
  cd snappy
  cmake_install -DSNAPPY_BUILD_TESTS=OFF  
}

function install_dwarf {
  if [ -f "/usr/local/lib/libdwarf.a" ]; then
    echo "Already installed!"
    return 
  fi 
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://github.com/davea42/libdwarf-code/archive/refs/tags/20210528.tar.gz dwarf
  cd dwarf
  ./configure --enable-shared=no
  make
  make check
  $SUDO make install
}

function install_re2 {
  if [ -f "/usr/local/lib/libre2.a" ]; then
    echo "Already installed!"
    return 
  fi 
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://github.com/google/re2/archive/refs/tags/2023-03-01.tar.gz re2
  cd re2
  $SUDO make install
}

function install_flex {
  if [ -f "/usr/local/lib/libfl.so.2.0.0" ]; then
    echo "already installed!"
    return 
  fi 
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz flex
  cd flex
  ./autogen.sh
  ./configure
  $SUDO make install
}

function install_lzo {
  if [ -f "/usr/local/lib/liblzo2.so.2.0.0" ];  then
    echo "already installed!"
    return
  fi 
  cd "${DEPENDENCY_DIR}"
  wget_and_untar http://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz lzo
  cd lzo
  ./configure --prefix=/usr/local --enable-shared --disable-static --docdir=/usr/local/share/doc/lzo-2.10
  make "-j$(nproc)"
  $SUDO make install
}

function install_boost {
  if [ -f "/usr/local/lib/libboost_log.so.1.84.0" ]; then
    echo "boost 1.84.0 already installed"
    return
  fi
  # Remove old version.
  sudo rm -f /usr/local/lib/libboost_* /usr/lib64/libboost_* /opt/rh/devtoolset-9/root/usr/lib64/dyninst/libboost_*
  sudo rm -rf /tmp/velox-deps/boost/ /usr/local/include/boost/ /usr/local/lib/cmake/Boost-1.72.0/
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://github.com/boostorg/boost/releases/download/boost-1.84.0/boost-1.84.0.tar.gz boost
  cd boost
  ./bootstrap.sh --prefix=/usr/local --with-python=/usr/bin/python3  --without-libraries=python
  $SUDO ./b2 "-j$(nproc)" -d0 install threading=multi
}


function install_protobuf {
  if [ -f "/usr/local/lib/libprotobuf.la" ] ; then
    echo "already installed!"
    return
  fi 
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://github.com/protocolbuffers/protobuf/releases/download/v21.4/protobuf-all-21.4.tar.gz protobuf-all-21.4
  cd protobuf-all-21.4
  ./configure  CXXFLAGS="-fPIC"  --prefix=/usr/local
  make "-j$(nproc)"
  $SUDO make install
}

function install_awssdk {
  if [ -f "/usr/local/lib64/libaws-crt-cpp.a" ] ; then
    echo "already installed!"
    return
  fi 
  cd "${DEPENDENCY_DIR}"
  github_checkout aws/aws-sdk-cpp 1.9.379 --depth 1 --recurse-submodules
  cmake_install -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS:BOOL=OFF -DMINIMIZE_SIZE:BOOL=ON -DENABLE_TESTING:BOOL=OFF -DBUILD_ONLY:STRING="s3;identity-management" 
}

function install_gtest {
  if [ -f "/usr/local/lib64/libgtest.so" ] ; then
    echo "already installed!"
    return
  fi 
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://github.com/google/googletest/archive/refs/tags/release-1.12.1.tar.gz googletest-1.12
  cd googletest-1.12
  mkdir -p build && cd build && cmake -DBUILD_GTEST=ON -DBUILD_GMOCK=ON -DINSTALL_GTEST=ON -DINSTALL_GMOCK=ON -DBUILD_SHARED_LIBS=ON ..
  make "-j$(nproc)"
  $SUDO make install
} 

function install_fmt {
  if [ -f "/usr/local/include/fmt/args.h" ]; then
    echo "already installed!"
    return
  fi 
  cd "${DEPENDENCY_DIR}"
  wget_and_untar https://github.com/fmtlib/fmt/archive/10.1.1.tar.gz fmt
  cd fmt
  cmake_install fmt -DFMT_TEST=OFF
}

function install_duckdb {
  if [ -f "/usr/local/lib/libduckdb_static.a" ]; then
    echo "already installed!"
    return
  fi 
  cd "${DEPENDENCY_DIR}"
  
  echo 'Building DuckDB'
  wget_and_untar https://github.com/duckdb/duckdb/archive/refs/tags/v0.8.1.tar.gz duckdb
  cd duckdb
  cmake_install -DBUILD_UNITTESTS=OFF -DENABLE_SANITIZER=OFF -DENABLE_UBSAN=OFF -DBUILD_SHELL=OFF -DEXPORT_DLL_SYMBOLS=OFF -DCMAKE_BUILD_TYPE=Release
}

function install_velox_deps_optional {
  run_and_time install_protobuf
  run_and_time install_awssdk
}

function install_velox_deps {
  run_and_time install_lzo
  run_and_time install_boost
  run_and_time install_re2
  run_and_time install_flex
  run_and_time install_openssl
  run_and_time install_gflags
  run_and_time install_glog
  run_and_time install_snappy
  run_and_time install_dwarf
  run_and_time install_fmt
  run_and_time install_folly
  run_and_time install_conda
  run_and_time install_duckdb
}
