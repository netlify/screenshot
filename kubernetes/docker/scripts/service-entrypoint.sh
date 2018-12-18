#!/bin/dumb-init

set -e

cd $PWD
exec gosu netlify "$@"
