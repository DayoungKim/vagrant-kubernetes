#!/bin/bash

echo -n "    default: Are you sure you want to destroy the 'default' VM? [y/N] "
read -r ans
if [[ "y" == "$ans" ]]; then
  find . -name "vagrant[0-9]*" -exec sh -c 'cd {}; vagrant destroy -f; cd ..; rm -r {}' \;
fi
