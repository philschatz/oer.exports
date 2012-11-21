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

Optional: download the following libraries and toss them into `./static/lib`

*  MathJax  ( Download from http://www.mathjax.org/download/ and the file `./static/lib/mathjax/MathJax.js` should exist )
*  d3       ( Put in `d3.js` from https://github.com/mbostock/d3 )
*  nv       ( Put in `nv.d3.js` and `nv.d3.css` from https://github.com/novus/nvd3 )
*  TangleJS ( git clone https://github.com/worrydream/Tangle.git )

And, to start it up (all one line)

    node bin/server.js
        --pdfgen ${PATH_TO_PRINCE_BINARY}
        --phantomjs ${PATH_TO_PHANTOMJS_BINARY}

Then, point your browser to the admin console at http://localhost:3001/

## "Ok, so what now?"

Deposit a piece of content (`example.cnxml`) and watch all the tables populate.
If they don't all end up completing successfully then probably the dependencies were not met
or you passed in the wrong command line arguments.

## "What are these tables?"

When you deposit a URL to a cnxml or collxml
  (eventually it'll only accept HTML files)
  several things happen:

1. The local cache of that URL is invalidated
2. The remote file is retrieved and converted to HTML using XSLT
3. This intermediate HTML file is POSTed and stored at `/intermediate/[id]`

At this point none of the links or images have been converted; they still have the original hrefs
but the HTML file has a few additional pieces in it:

* A `meta` element that stores the original URL so links/images can be converted to absolute URLs
* `script` tags for javascript tools like MathJax

The next step takes the HTML and

1. Loads the javascript libraries
2. Enqueues a task to GET the remote URLs and store them locally in `/resources/[uuid]`
3. Convert links to absolute URLs
4. If a link has the special class `xinclude` then a deposit is done
   to generate a PDF for that content (it may already be cached)
5. Once all these tasks have spawned
   (since they're `Promises` we already know what their id/URL will be)
   the HTML is POSTed to `/content/[id]`

The next step takes the HTML with new local id's and waits until each piece of content
is deposited to `/content[id1,2,3]`.

1. As they appear in `/content` each one is loaded and included in the DOM
   (these were links with `.xinclude`)
2. The resulting HTML file is POSTed to `/assembled/[id]`.

Finally, we can actually generate a PDF. All the modules have been assembled into
one large HTML file and the images have been loaded and saved locally in `/resources/`.

The PDF is then stored at `/content/[id].pdf`.


# "Cool! What else can I do?"

Here are some notes I haven't gotten around to rewriting:

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
