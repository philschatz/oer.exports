# What is this?

This is a mock implementation of a proposed API for generating PDFs and EPUBs in a federated OER Repository.


# Ooh, let me see!

To start it up you'll need nodejs (see http://nodejs.org ) and the node package manager (npm).

To download the dependencies

    npm install .

* Install `rsvg-convert` (`apt-get install rsvg` on Debian/Ubuntu).
  Make sure `rsvg-convert -v` works from the command line.
* Download `phantomjs` from http://phantomjs.org
* Download PrinceXML from http://princexml.com
* Check out http://github.com/Connexions/rhaptos.cnxmlutils (`cnxml2html` branch)
  and put it in `./externals`

Optional: download the following libraries and toss them into `./static/lib`

*  MathJax  ( Download from http://www.mathjax.org/download/ and the file `./static/lib/mathjax/MathJax.js` should exist )
*  d3       ( Put in `d3.js` from https://github.com/mbostock/d3 )
*  nv       ( Put in `nv.d3.js` and `nv.d3.css` from https://github.com/novus/nvd3 )
*  TangleJS ( git clone https://github.com/worrydream/Tangle.git )

And, to start it up

    node bin/server.js --pdfgen ${PATH_TO_PRINCE_BINARY} --phantomjs ${PATH_TO_PHANTOMJS_BINARY}


Then, point your browser to the admin interface at http://localhost:3000/

From the admin page use the input box in "Deposit new content from a URL" to point to a CNXML/CollXML file.
This will pull in and clean up all related documents.
Some examples are on the admin page in a dropdown.

You can also download a collection and unzip it into the `./static` directory.
You will need to make the following changes to the `collection.xml` file:

* change all of the `@repository` urls to be `repository="/col123"`
  (where `col123` is the collection id)
* change all the `@version` attributes to be `version="index_auto_generated.cnxml"`

Once you submit it, each piece of content goes through 4 phases:

* `/intermediate/` Converts CNXML to HTML (go to /intermediate/# to see either the list of content that is done or see the HTML of those that are completed)
* `/content/` Converts canvases and dynamic content to SVG, renames local hrefs to be absolute, requests xincluded content be converted
* `/assembled/` Includes the xincluded content into 1 big file
* `/content/#.pdf` Uses HTML at `/assembled/#` to create a PDF (TODO)
* `/content/#.epub` Uses HTML at `/assembled/#` to create an EPUB
