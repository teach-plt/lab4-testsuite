#!/bin/sh

if [ "$1" == "" -o  "$1" == "-h" -o "$1" == "--help" ]; then
  echo "PLT lab 4 testsuite runner"
  echo "usage: $0 DIRECTORY"
  exit 1
fi

cabal run plt-test-lab4 -- "$1"

# EOF
