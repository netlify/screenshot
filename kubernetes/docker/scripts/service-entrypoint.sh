#!/bin/dumb-init /bin/bash

set -e

cd $PWD
exec gosu netlify "$@"
