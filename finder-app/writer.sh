#!/bin/bash

if [ $# != 2 ]
  then
    echo "2 arguments required: writefile writestr"
    exit 1
fi

writefile=$1
writestr=$2

# create path
if ! (mkdir -p $(dirname $writefile)) && touch $writefile;
  then
    echo "File could not be created"
    exit 1
fi

# write in file
if ! (echo $writestr >> $writefile)
  then
    echo "Cannot write in file"
    exit 1
fi

exit 0
