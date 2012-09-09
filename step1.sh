#! /bin/bash -x -v
FROM_URL=$1
TO_URL=$2
ID=$3
DEPOSIT_URL=$4 # For Xinclude documents
LOCALHOST=$5
ORIGINAL_ID=$6

# Find the current directory
ROOT_DIR=`dirname "$0"`
ROOT_DIR=`cd "$ROOT"; pwd`

PHANTOMJS_BIN=${ROOT_DIR}/external/phantomjs/bin/phantomjs
CONTENT_TO_PRESENTATION_XSL=${ROOT_DIR}/external/oer.exports/xsl/cnxml-clean.xsl
CNXML2HTML5_XSL=${ROOT_DIR}/external/rhaptos.cnxmlutils/rhaptos/cnxmlutils/xsl/collxml-to-html5.xsl # cnxml-to-html5.xsl
OER_INTERACTIVE=${ROOT_DIR}/external/oer.interactive

TEMP_DIR=$(pwd)

# Emulate the javascript stored in the HTML (and run mathjax)
${PHANTOMJS_BIN} --local-to-remote-url-access=yes --web-security=yes ${ROOT_DIR}/step1.coffee ${ROOT_DIR} ${FROM_URL} ${TO_URL} ${DEPOSIT_URL} ${LOCALHOST} ${ID}
