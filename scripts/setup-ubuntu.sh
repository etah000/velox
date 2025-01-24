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

# This script documents setting up a Centos8 host for Velox
# development.  Running it should make you ready to compile.
#
# Environment variables:
# * INSTALL_PREREQUISITES="N": Skip installation of packages for build.
# * PROMPT_ALWAYS_RESPOND="n": Automatically respond to interactive prompts.
#     Use "n" to never wipe directories.
#
# You can also run individual functions below by specifying them as arguments:
# $ scripts/setup-ubuntu.sh install_googletest install_fmt
#

# Minimal setup for Ubuntu 20.04.
set -eufx -o pipefail
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")
source $SCRIPTDIR/setup-common-deps.sh

export CMAKE_BUILD_TYPE=Release
SUDO="sudo "

# Install packages required for build.
function install_build_prerequisites {
  ${SUDO} apt update
  # The is an issue on 22.04 where a version conflict prevents glog install,
  # installing libunwind first fixes this.
  ${SUDO} apt install -y libunwind-dev
  ${SUDO} apt install -y \
    build-essential \
    python3-pip \
    ccache \
    curl \
    checkinstall \
    git \
    wget   

  run_and_time install_cmake
  run_and_time install_ninja
}

# Install packages required for build.
function install_velox_deps_from_apt {
  ${SUDO} apt install -y \
    libc-ares-dev \
    libcurl4-openssl-dev \
    libicu-dev \
    libdouble-conversion-dev \
    libbz2-dev \
    libgmock-dev \
    libevent-dev \
    liblz4-dev \
    libzstd-dev \
    libsodium-dev \
    libelf-dev \
    bison \
    tzdata

  install_velox_deps_from_apt

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

  run_and_time install_fizz
  run_and_time install_wangle
  run_and_time install_mvfst
  run_and_time install_fbthrift
  run_and_time install_arrow
  run_and_time install_protobuf
  run_and_time install_curl
  run_and_time install_cpr
}


(return 2> /dev/null) && return # If script was sourced, don't run commands.

(
  if [[ $# -ne 0 ]]; then
    for cmd in "$@"; do
      run_and_time "${cmd}"
    done
    echo "All specified dependencies installed!"
  else
    if [ "${INSTALL_PREREQUISITES:-Y}" == "Y" ]; then
      echo "Installing build dependencies"
      run_and_time install_build_prerequisites
    else
      echo "Skipping installation of build dependencies since INSTALL_PREREQUISITES is not set"
    fi
    install_velox_deps
    echo "All dependencies for Velox installed!"
  fi
)

