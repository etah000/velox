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

source $SCRIPTDIR/setup-common-deps.sh

BUILD_DUCKDB="${BUILD_DUCKDB:-true}"

LINUX_DISTRIBUTION=$(. /etc/os-release && echo ${ID})

# shellcheck disable=SC2037
SUDO="sudo "


function dnf_install {
  $SUDO dnf install -y -q --setopt=install_weak_deps=False "$@"
}

function yum_install {
  $SUDO yum install -y "$@"
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

if [[ "$LINUX_DISTRIBUTION" == "centos" ]]; then
  $SUDO dnf makecache
  # dnf install dependency libraries
  dnf_install epel-release dnf-plugins-core # For ccache, ninja
fi 
# PowerTools only works on CentOS8
# dnf config-manager --set-enabled powertools
dnf_install ccache git wget which libevent-devel \
  openssl-devel libzstd-devel lz4-devel double-conversion-devel \
  curl-devel libxml2-devel libgsasl-devel libuuid-devel patch

# Required for Thrift
dnf_install autoconf automake libtool bison python3 python3-devel

# Required for build flex
dnf_install gettext-devel texinfo help2man

# dnf_install conda

if [[ "$LINUX_DISTRIBUTION" == "centos" ]]; then
  $SUDO yum makecache
  yum_install centos-release-scl
  yum_install devtoolset-9
  source /opt/rh/devtoolset-9/enable || exit 1
fi 

gcc --version

# Build from source
[ -d "$DEPENDENCY_DIR" ] || mkdir -p "$DEPENDENCY_DIR"

run_and_time install_cmake
run_and_time install_ninja

install_velox_deps_optional
install_velox_deps
