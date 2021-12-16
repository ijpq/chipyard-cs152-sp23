#!/usr/bin/env bash

# exit script if any command fails
set -e
set -o pipefail

# Check that git version is at least 1.7.8
MYGIT=$(git --version)
MYGIT=${MYGIT#'git version '} # Strip prefix
case ${MYGIT} in
[1-9]*) ;;
*) echo 'warning: unknown git version' ;;
esac
MINGIT="1.8.5"
if [ "$MINGIT" != "$(echo -e "$MINGIT\n$MYGIT" | sort -V | head -n1)" ]; then
  echo "This script requires git version $MINGIT or greater. Exiting."
  false
fi

# On macOS, use GNU readlink from 'coreutils' package in Homebrew/MacPorts
if [ "$(uname -s)" = "Darwin" ] ; then
    READLINK=greadlink
else
    READLINK=readlink
fi

# If BASH_SOURCE is undefined we may be running under zsh, in that case
# provide a zsh-compatible alternative
DIR="$(dirname "$($READLINK -f "${BASH_SOURCE[0]:-${(%):-%x}}")")"
CHIPYARD_DIR="$(dirname "$DIR")"

cd "$CHIPYARD_DIR"

(
    # Blocklist of submodules to initially skip:
    # - Toolchain submodules
    # - Generators with huge submodules (e.g., linux sources)
    # - FireSim until explicitly requested
    # - Hammer tool plugins
    git_submodule_exclude() {
        # Call the given subcommand (shell function) on each submodule
        # path to temporarily exclude during the recursive update
        for name in \
            toolchains/*-tools/*/ \
            toolchains/libgloss \
            toolchains/qemu \
            generators/sha3 \
            generators/gemmini \
            sims/firesim \
            software/nvdla-workload
            vlsi/hammer-cadence-plugins \
            vlsi/hammer-synopsys-plugins \
            vlsi/hammer-mentor-plugins \
            software/firemarshal \
            fpga/fpga-shells
        do
            "$1" "${name%/}"
        done
    }

    _skip() { git config --local "submodule.${1}.update" none ; }
    _unskip() { git config --local --unset-all "submodule.${1}.update" || : ; }

    trap 'git_submodule_exclude _unskip' EXIT INT TERM
    git_submodule_exclude _skip
    git submodule update --init --recursive #--jobs 8
)

# Non-recursive clone to exclude riscv-linux
git submodule update --init generators/sha3

# Non-recursive clone to exclude gemmini-software
git submodule update --init generators/gemmini
git -C generators/gemmini/ submodule update --init --recursive software/gemmini-rocc-tests

# Minimal non-recursive clone to initialize sbt dependencies
git submodule update --init sims/firesim
git config --local submodule.sims/firesim.update none

# Only shallow clone needed for basic SW tests
git submodule update --init software/firemarshal

# Configure firemarshal to know where our firesim installation is
if [ ! -f ./software/firemarshal/marshal-config.yaml ]; then
  echo "firesim-dir: '../../sims/firesim/'" > ./software/firemarshal/marshal-config.yaml
fi

echo "# line auto-generated by init-submodules-no-riscv-tools.sh" >> env.sh
echo '__DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]:-${(%):-%x}}")")"' >> env.sh
echo "PATH=\$__DIR/bin:\$PATH" >> env.sh
echo "PATH=\$__DIR/software/firemarshal:\$PATH" >> env.sh
