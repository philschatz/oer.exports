# Set export objects for node and coffee to a function that generates a sfw server.
module.exports = exports = (argv) ->

  SVG_TO_PNG_DPI = 12

  #### Dependencies ####
  # anything not in the standard library is included in the repo, or
  # can be installed with an:
  #     npm install
  spawn       = require('child_process').spawn
  express     = require('express')
  path        = require('path')
  fs          = require('fs') # Just to load the HTML files
  Q           = require('q') # Promise library
  _           = require('underscore')
  jsdom       = require('jsdom')
  URI         = require('URIjs')
  url         = require('url')
  hbs         = require('hbs')
  EventEmitter = require('events').EventEmitter

  # jsdom only seems to like REMOTE urls to scripts (like jQuery)
  # So, instead, we manually attach jQuery to the window
  jQueryFactory = require('../jquery-module')


  # Error if required args are not included
  REQUIRED_ARGS = [ 'pdfgen' ]
  REQUIRED_ARGS.forEach (arg) ->
    if not argv[arg]
      console.error "Required command line argument missing: #{arg}"
      throw new Error "Required command line argument missing"


  # Enable easy-to-read stack traces
  #Q.longStackSupport = true

  DATA_PATH = path.join(__dirname, '..', 'data')
  JQUERY_PATH = path.join(__dirname, '..', 'node_modules/jquery-component/dist/jquery.js')
  JQUERY_CODE = fs.readFileSync(JQUERY_PATH, 'utf-8')

  class Task
    constructor: () ->
      @created = new Date()
      @history = []

    attachPromise: (@promise) ->
      @promise.progress (message) =>
        @notify(message)

    notify: (message) ->
      # Only keep the 50 most recent messages
      if @history.length > 50
        @history.splice(0,1)

      @history.push(message)

    toJSON: () ->
      status = 'UNKNOWN'
      status = 'COMPLETED' if @promise.isResolved()
      status = 'FAILED'    if @promise.isRejected()
      status = 'PENDING'   if not @promise.isFulfilled()
      return {
        created:  @created
        history:  @history
        status:    status
      }

  # Stores the Promise for a PDF
  STATE = null


  #### Spawns ####
  env =
    env: process.env
  env.env['PDF_BIN'] = argv.pdfgen

  errLogger = (task) -> (data) ->
    lines = data.toString().split('\n')
    for line in lines
      if line.length > 1
        task.notify("STDERR: #{line}")
        console.error("STDERR: #{line}")

  spawnPullCommits = (promise, gitUrl, branch) ->
    # TODO: clone the repo if it does not exist yet
    cwd = './data'
    child = spawn('git', [ 'pull' ], {cwd:cwd})
    child.stderr.on 'data', childLogger(true, promise)

    deferred = Q.defer()
    child.on 'exit', (code) -> deferred.resolve()
    return deferred.promise


  fsReadDir   = () -> Q.nfapply(fs.readdir,   arguments)
  fsStat      = () -> Q.nfapply(fs.stat,      arguments)
  fsReadFile  = () -> Q.nfapply(fs.readFile,  arguments)

  # Given an HTML (or XML) string, return a Promise of a jQuery object
  buildJQuery = (uri, xml) ->
    deferred = Q.defer()
    #jsdom.env html, [ "file://#{JQUERY_PATH}" ], (err, window) ->
    jsdom.env
      html: xml
      # src: [ "//<![CDATA[\n#{JQUERY_CODE}\n//]]>" ]
      # scripts: [ "http://code.jquery.com/jquery.js" ] # [ "file://#{JQUERY_PATH}" ]
      # scripts: [ "#{argv.u}/jquery.js" ]
      done: (err, window) ->
        return deferred.reject(err) if err

        # Attach jQuery to the window
        jQueryFactory(window)

        if window.jQuery
          deferred.notify {msg: 'jQuery built for file', path: uri.toString()}
          deferred.resolve(window.jQuery)
        else
          deferred.reject('Problem loading jQuery...')
    return deferred.promise


  # Concatenate all the HTML files in an EPUB together
  assembleHTML = (task) ->

    allHtml = []

    # 1. Read the META-INF/container.xml file
    # 2. Read the first OPF file
    # 3. Read the ToC Navigation file (relative to the OPF file)
    # 4. Read each HTML file linked to from the ToC file (relative to the ToC file)

    root = new URI(DATA_PATH + '/')

    readUri = (uri) ->
      task.notify {msg:'Reading file', uri:uri.toString()}
      fsReadFile(uri.absoluteTo(root).toString())


    # Check that a mimetype file exists
    task.notify('Checking if mimetype file exists')
    return readUri(new URI('mimetype'))
    .then (mimeTypeStr) ->
      # Fail if the mimetype file is invalid
      if 'application/epub+zip' != mimeTypeStr.toString().trim()
        return Q.defer().reject('Invalid mimetype file')

      # 1. Read the META-INF/container.xml file
      containerUri = new URI('META-INF/container.xml')
      return readUri(containerUri)
      .then (containerXml) ->
        return buildJQuery(containerUri, containerXml)
        .then ($) ->
          # 2. Read the first OPF file
          $opf = $('container > rootfiles > rootfile[media-type="application/oebps-package+xml"]').first()
          opfPath = $opf.attr('full-path')
          opfUri = new URI(opfPath)
          return readUri(opfUri)
          .then (opfXml) ->
            # Find the absolute path to the ToC navigation file
            return buildJQuery(opfUri, opfXml)
            .then ($) ->
              $navItem = $('package > manifest > item[properties^="nav"]')
              navPath = $navItem.attr('href')

              # 3. Read the ToC Navigation file (relative to the OPF file)
              task.notify('Reading ToC Navigation file')
              navUri = new URI(navPath)
              return readUri(navUri.absoluteTo(opfUri))
              .then (navHtml) ->
                return buildJQuery(navUri, navHtml)
                .then ($) ->
                  # 4. Read each HTML file linked to from the ToC file (relative to the ToC file)
                  $toc = $('nav')

                  anchorPromises = _.map $toc.find('a'), (a) ->
                    $a = $(a)
                    href = $a.attr('href')

                    fileUri = (new URI(href)).absoluteTo(navUri)
                    return readUri(fileUri)
                    .then (html) ->
                      return buildJQuery(fileUri, html)
                      .then ($) ->
                        allHtml.push($('body')[0].innerHTML)

                  # Concatenate all the HTML once they have all been parsed
                  return Q.all(anchorPromises)
                  .then () ->
                    task.notify {msg:'Combining HTML files', count:allHtml.length}
                    joinedHtml = allHtml.join('\n')
                    task.notify {msg:'Combined HTML files', size:joinedHtml.length}
                    return joinedHtml


  spawnGeneratePDF = (html, task) ->
    deferred = Q.defer()
    child = spawn(argv.pdfgen, [ '--input=xhtml', '--verbose', '--output=/dev/stdout', '-' ], env)
    chunks = []
    chunkLen = 0

    child.stderr.on 'data', errLogger(task)

    child.stdout.on 'data', (chunk) ->
      chunks.push chunk
      chunkLen += chunk.length

    child.stdin.write html, 'utf-8', () ->
      deferred.notify('Sent input to PDFGEN')
      child.stdin.end()

    child.on 'exit', (code) ->
      return deferred.reject('PDF generation failed') if 0 != code

      buf = new Buffer(chunkLen)
      pos = 0
      for chunk in chunks
        chunk.copy(buf, pos)
        pos += chunk.length
      deferred.resolve(buf)

    return deferred.promise


  # Create the main application object, app.
  app = express.createServer()

  # defaultargs.coffee exports a function that takes the argv object that is passed in and then does its
  # best to supply sane defaults for any arguments that are missing.
  argv = require('./defaultargs')(argv)

  #### Express configuration ####
  # Set up all the standard express server options,
  # including hbs to use handlebars/mustache templates
  # saved with a .html extension, and no layout.
  app.configure( ->
    app.set('view options', layout: false)
    app.use(express.cookieParser())
    app.use(express.bodyParser())
    app.use(express.methodOverride())
    app.use(express.session({ secret: 'notsecret'}))
    app.use(app.router)
    app.use(express.static(path.join(__dirname, '..', 'static')))
  )

  ##### Set up standard environments. #####
  # In dev mode turn on console.log debugging as well as showing the stack on err.
  app.configure('development', ->
    app.use(express.errorHandler({ dumpExceptions: true, showStack: true }))
    argv.debug = console? and true
  )

  # Show all of the options a server is using.
  console.log argv if argv.debug

  # Swallow errors when in production.
  app.configure('production', ->
    app.use(express.errorHandler())
  )

  #### Routes ####

  # JSDOM seems to need a website. instead of pointing to jquery.com, use localhost to serve it
  app.get '/jquery.js', (req, res, next) ->
    res.header('Content-Type', 'application/x-javascript; charset=utf-8')
    res.send(JQUERY_CODE)

  app.get '/', (req, res, next) ->
    payload = req.param('payload')

    # spawnPullCommits(promise)
    # .fail( (err) -> console.error(err))
    # .then () ->
    #   assembleHTML(promise)
    #   .then (html) ->
    #     spawnGeneratePDF(promise, html)

    task = new Task()
    promise = assembleHTML(task)
    .fail( (err) -> console.error(err))
    .then (htmlFragment) ->
      html = """<?xml version='1.0' encoding='utf-8'?>
                <!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.1//EN' 'http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd'>
                <html xmlns="http://www.w3.org/1999/xhtml">
                  <head>
                    <meta http-equiv="Content-Type" content="application/xhtml+xml; charset=utf-8"/>
                  </head>
                  <body>
                  #{htmlFragment}
                  </body>
                </html>"""

      return spawnGeneratePDF(html, task)

    task.attachPromise(promise)

    STATE = task

    # Send OK
    res.send(task.toJSON())


  app.get '/:repoUser/:repoName/status', (req, res) ->
    task = STATE

    return res.status(404).send('NOT FOUND. Try adding a commit Hook first.') if not task

    res.send(task.toJSON())

  app.get '/:repoUser/:repoName/pdf', (req, res) ->
    task = STATE

    return res.status(404).send('NOT FOUND. Try adding a commit Hook first.') if not task

    promise = task.promise
    if promise.isResolved()
      res.header('Content-Type', 'application/pdf')
      task.promise.done (data) ->
        res.send(data)
    else if promise.isRejected()
      res.status(400).send(task.toJSON())
    else if not promise.isFulfilled()
      res.status(202).send(task.toJSON())
    else
      throw new Error('BUG: Something fell through')

  #### Start the server ####

  app.listen(argv.p, argv.o if argv.o)
  # When server is listening emit a ready event.
  app.emit "ready"
  console.log("Server listening in mode: #{app.settings.env}")

  # Return app when called, so that it can be watched for events and shutdown with .close() externally.
  app
