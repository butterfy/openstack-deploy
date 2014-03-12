#! /bin/bash

if [ `whoami` != "root" ]; then
    echo "The script only run in root."
    exit
fi
