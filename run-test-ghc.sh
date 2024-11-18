#!/usr/bin/env sh

# Programming Language Technology (Chalmers DAT151 / GU DIT231)
# (C) 2022-24 Andreas Abel
# All rights reserved.

if [ "$1" == "" -o  "$1" == "-h" -o "$1" == "--help" ]; then
  echo "PLT lab 4 testsuite runner"
  echo "usage: $0 [OPTIONS] DIRECTORY"
  echo "Takes the same options as plt-test-lab4:"
  runghc plt-test-lab4
  exit 1
fi

runghc plt-test-lab4 -- "$@"

# EOF
