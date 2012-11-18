TEMPDIR="tmp-generate-pdf"
ZIPNAME="tmp.zip"

rm -rf ${TEMPDIR}
mkdir ${TEMPDIR}
cd ${TEMPDIR}
curl -o ${ZIPNAME} ${URL}
unzip ${ZIPNAME}
# Unzip creates a col123_complete dir and puts everything underneath.
# Just move all those files back up
rm ${ZIPNAME}
mv */* .

cd ..

python collectiondbk2pdf.py -p ${PRINCEXML_PATH} -s ${STYLE} -d ${TEMPDIR} /dev/stdout
