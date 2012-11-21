#! /bin/bash
FROM_URL=$1
TO_URL=$2
ID=$3
DEPOSIT_URL=$4 # For Xinclude documents
LOCALHOST=$5
ORIGINAL_ID=$6

# Find the current directory
ROOT_DIR=`dirname "$0"`
ROOT_DIR=`cd "$ROOT"; pwd`

TEMP_DIR=$(pwd)

# Emulate the javascript stored in the HTML (and run mathjax)
${PHANTOMJS_BIN} --local-to-remote-url-access=yes --web-security=yes ${ROOT_DIR}/step1.coffee ${ROOT_DIR} ${FROM_URL} ${TO_URL} ${DEPOSIT_URL} ${LOCALHOST} ${ID}
