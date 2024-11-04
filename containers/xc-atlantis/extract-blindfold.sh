#!/bin/sh
#
# Unseals the blindfolded secrets to local files before launching atlantis

set -x

[ -n "${UNSEAL_JSON}" ] && /usr/local/bin/unseal "${UNSEAL_JSON}"
