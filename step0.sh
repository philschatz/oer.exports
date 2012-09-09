#! /bin/bash
FROM_URL=$1
TO_URL=$2
ID=$3
DEPOSIT_URL=$4 # For Xinclude documents

# Find the current directory
ROOT_DIR=`dirname "$0"`
ROOT_DIR=`cd "$ROOT"; pwd`

CONTENT_TO_PRESENTATION_XSL=${ROOT_DIR}/xsl/cnxml-clean.xsl
CNXML2HTML5_XSL=${ROOT_DIR}/external/rhaptos.cnxmlutils/rhaptos/cnxmlutils/xsl/collxml-to-html5.xsl # cnxml-to-html5.xsl

TEMP_DIR=$(pwd)
CNXML_FILE=${TEMP_DIR}/${ID}.cnxml
CNXML2_FILE=${TEMP_DIR}/${ID}.2.cnxml
HTML_FILE=${TEMP_DIR}/${ID}.html
XHTML_FILE=${TEMP_DIR}/${ID}.xhtml

curl -o ${CNXML_FILE} ${FROM_URL}

# Convert Content MathML to Presentation MathML
xsltproc ${CONTENT_TO_PRESENTATION_XSL} ${CNXML_FILE} > ${CNXML2_FILE}

# Convert from cnxml (or collxml) to xhtml
echo "<!DOCTYPE html>" > ${HTML_FILE}
echo "<html xmlns='http://www.w3.org/1999/xhtml'><head>" >> ${HTML_FILE}
echo "  <meta href='${FROM_URL}'/>" >> ${HTML_FILE}
echo "</head>" >> ${HTML_FILE}
#cat ${OER_INTERACTIVE}/inject-before.html > ${HTML_FILE}

xsltproc ${CNXML2HTML5_XSL} ${CNXML2_FILE} >> ${HTML_FILE}
echo "</html>" >> ${HTML_FILE}

# POST the result back to the server
curl --silent --show-error --data-urlencode contents@${HTML_FILE} ${TO_URL}