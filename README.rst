==============
 What is this?
==============

This is a mock implementation of a proposed API for generating PDFs and EPUBs in a federated OER Repository.


==================
 Ooh, let me see!
==================

To start it up you'll need nodejs (see http://nodejs.org ) and the node package manager (npm).

To download the dependencies::

  $ npm install .
  
Check out related github projects (and put them in ./external):

  http://github.com/philschatz/oer.epubcss (oer.exports-html branch)
  http://github.com/Connexions/rhaptos.cnxmlutils (cnxml2html branch)
  PhantomJS directory ( ./external/phantomjs/bin/phantomjs should work)
  PrinceXML ( ./external/prince/bin/prince should work)

Also, download MathJax and toss it into ./lib (the file ./lib/mathjax/MathJax.js should exist)

And, to start it up::

  $ node bin/server.js --pdfgen /path/to/prince-or-wkhtml2pdf

Or, to specify a port and hostname::

  $ node bin/server.js -p 3001 --pdfgen /path/to/prince

Optionally you can use `wkhtml2pdf` to generate a PDF by using the ``--pdfgen /path/to/wkhtml2pdf`` command line option.

Then, point your browser to the admin interface at http://localhost:3000/

From the admin page use the input box in "Deposit new content from a URL" to point to a CNXML/CollXML file. This will pull in and clean up all related documents. Some examples include:

  http://philschatz.github.com/oer.interactive/example.cnxml   # CNXML with cool graphics
  http://cnx.org/content/m9003/2.68/     # Module CNXML file
  http://cnx.org/content/col10514/1.4/   # Collection of test modules
  # Or, unzip a collection to ./static and make the following changes to the collection.xml
  # - change all of the @repository urls to be repository="/col123"
  # - change all the @version attributes to be version="index_auto_generated.cnxml"

Once you submit it, each piece of content goes through 4 phases:
* /intermediate/ Converts CNXML to HTML (go to /intermediate/# to see either the list of content that is fone or see the HTML of those that are completed)
* /content/ Converts canvases and dynamic content to SVG, renames local hrefs to be absolute, requests xincluded content be converted
* /assembled/ Includes the xincluded content into 1 big file
* /content.pdf Uses HTML at /assembled/# to create a PDF (TODO)
* /content.epub Uses HTML at /assembled/# to create an EPUB
