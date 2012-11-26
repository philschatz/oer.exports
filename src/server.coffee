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
  url         = require('url')
  hbs         = require('hbs')
  fs          = require('fs') # Just to load jQuery
  EventEmitter = require('events').EventEmitter
  # Authentication machinery
  passport    = new (require('passport')).Passport()
  OpenIDstrat = require('passport-openid').Strategy


  # Error if required args are not included
  REQUIRED_ARGS = [ 'phantomjs', 'pdfgen' ]
  REQUIRED_ARGS.forEach (arg) ->
    if not argv[arg]
      console.error "Required command line argument missing: #{arg}"
      throw new Error "Required command line argument missing"



  #### State ####
  # Stores in-memory state
  class Promise extends EventEmitter
    constructor: (prerequisite) ->
      #events.push @
      @status = 'PENDING'
      @created = new Date()
      @history = []
      @isProcessing = true
      @data = null
      if prerequisite?
        that = @
        prerequisite.on 'update', (msg) -> that.update "Prerequisite update: #{msg}"
        prerequisite.on 'fail', () ->
          that.update 'Prerequisite task failed'
          that.fail()
        prerequisite.on 'finish', (_, mimeType) -> that.update "Prerequisite finished generating object with mime-type=#{mimeType}"
    # Send either the data (if available), or a HTTP Status with this JSON
    send: (res) ->
      if @isProcessing
        res.status(202).send @
      else if @data
        res.header('Content-Type', @mimeType)
        res.send @data
      else
        res.status(404).send @
    update: (msg) ->
      #if @status == 'FINISHED' or @status == 'FAILED'
      #  message = @history[@history.length-1]
      #  err = { event: @, message: "This event already completed with status #{@status} and message='#{message}'", newMessage: msg }
      #  console.log err
      #  throw err
      @modified = new Date()
      @history.push msg
      if @history.length > 50
        @history.splice(0,1)
      @emit('update', msg)

    work: (message, @status='WORKING') ->
      @update(message)
      @emit('work')
    wait: (message, @status='PAUSED') ->
      @update(message)
      @emit('work')

    fail: (msg) ->
      @update msg
      @isProcessing = false
      @status = 'FAILED'
      @data = null
      @emit('fail')
    finish: (@data, @mimeType='text/html; charset=utf-8') ->
      @update "Generated file"
      @isProcessing = false
      @status = 'FINISHED'
      @emit('finish', @data, @mimeType)

  intermediate = {}
  content = {}
  assembled = {}
  pdfs = {}
  globalLookups = {}
  lookups = {}
  resources = []
  resourcesQueueIndex = 0
  resourcesProcessing = false
  hashId = 0


  #### Spawns ####
  env =
    env: process.env
  env.env['PHANTOMJS_BIN'] = argv.phantomjs
  env.env['PDF_BIN'] = argv.pdfgen

  childLogger = (isError, id, promise) -> (data) ->
    lines = data.toString().split('\n')
    for line in lines
      if line.length > 1
        if isError
          # TODO: Cause the promise to fail
          promise.update "ERROR: #{line}"
          console.error("ERROR id=#{id}: #{line}")
        else
          promise.update line
          console.log("id=#{id}: #{line}")

  spawnGeneratePDF = (id, promise) ->
    href = "#{argv.u}/assembled/#{id}"
    console.log ("id=#{id} Generating PDF")
    child = spawn(argv.pdfgen, [ '--input=xhtml', "--style=static/css/ccap-physics.css", '--verbose', '--output=/dev/stdout', href ], env)
    chunks = []
    chunkLen = 0
    child.stdout.on 'data', (chunk) ->
      chunks.push chunk
      chunkLen += chunk.length
    child.on 'exit', (code) ->
      buf = new Buffer(chunkLen)
      pos = 0
      for chunk in chunks
        chunk.copy(buf, pos)
        pos += chunk.length
      promise.finish(buf, 'application/pdf')
    child.stderr.on 'data', childLogger(true, id, promise)

  spawnConvertSVGIfNeeded = () ->
    if resourcesQueueIndex < resources.length and not resourcesProcessing
      resourcesProcessing = true
      console.log ("id=SVG Starting resourceId=#{resourcesQueueIndex}")
      promise = resources[resourcesQueueIndex]
      child = spawn('rsvg-convert', [ '--keep-aspect-ratio', "--dpi-x=#{SVG_TO_PNG_DPI}", "--dpi-y=#{SVG_TO_PNG_DPI}" ], env)
      chunks = []
      chunkLen = 0
      child.stdin.write(promise.svg)
      child.stdin.end()
      child.stdout.on 'data', (chunk) ->
        chunks.push chunk
        chunkLen += chunk.length
      child.on 'exit', (code) ->
        resourcesProcessing = false
        png = new Buffer(chunkLen)
        pos = 0
        for chunk in chunks
          chunk.copy(png, pos)
          pos += chunk.length
        promise.finish(png, 'image/png')
        resourcesQueueIndex++
        spawnConvertSVGIfNeeded()
      child.stderr.on 'data', childLogger(true, 'svg2png', promise)


  spawnGenerateStep = (step, fromUrl, toUrl, id, promise) ->
    console.log "Spawning step#{step}.sh [#{fromUrl}, #{toUrl}, #{id}, #{argv.u}/deposit, #{argv.u}]"
    if not promise
      console.error "ERROR: Spawned without a promise! id=#{id}"
    child = spawn('sh', ['-xv', "step#{step}.sh", fromUrl, toUrl, id, "#{argv.u}/deposit", "#{argv.u}"], env)
    child.stdout.on 'data', childLogger(false, id, promise)
    child.stderr.on 'data', childLogger(true, id, promise)

  # Create the main application object, app.
  app = express.createServer()

  # defaultargs.coffee exports a function that takes the argv object that is passed in and then does its
  # best to supply sane defaults for any arguments that are missing.
  argv = require('./defaultargs')(argv)

  addToGlobal = (href) ->
    if href not of globalLookups
      id = hashId++
      globalLookups[href] = id
      id
    else
      globalLookups[href]


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
    app.use(passport.initialize())
    app.use(passport.session()) # Must occur after express.session()
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
  # Routes currently make up the bulk of the Express
  # server. Most routes use literal names,
  # or regexes to match, and then access req.params directly.

  ##### Redirects #####
  # Common redirects that may get used throughout the routes.
  app.redirect('index', (req, res) ->
    '/admin.html'
  )

  ##### Get routes #####
  # Routes have mostly been kept together by http verb

  # Deposit a URL to convert to PDF/EPUB
  # This can be any URL (for federation)
  deposit = (href, originalId) ->
    console.log "Received deposit request for #{href} with originalId=#{originalId}"
    id = addToGlobal(href)
    lookups[id] = {}
    if originalId?
      lookups[originalId][href] = id

    href = href + 'source' if href.search('cnx.org') >= 0
    # Disabled "/source" for local content: spawnGenerateStep(0, href + '/source', "#{argv.u}/intermediate/#{id}", id)

    # If we already generated this URL then don't spawn it again
    if id not of intermediate or not originalId?

      # Create all the promises (to be filled out later)
      intermediate[id] = new Promise()
      content[id] = new Promise(intermediate[id])
      assembled[id] = new Promise(content[id])
      pdfs[id] = new Promise(assembled[id])

      spawnGenerateStep(0, href, "#{argv.u}/intermediate/#{id}", id, intermediate[id])

    id
  # Accept GET and POST Submissions
  app.all('/deposit', (req, res, next) ->
    href = req.param('new')
    originalId = req.param('original')
    id = deposit(href, originalId)
    #res.send "#{argv.u}/content/#{id}"
    # NOTE: We're sending just the ID because things like the xinclude pass use just the id.
    # Ideally this would return "/content/#{id}"
    if originalId?
      res.send "#{id}"
    else
      res.send "/content/#{id}"
  )

  # For debugging
  getTasks = (path, table) ->
    ret = []
    for id, val of table
      ret.push
        id: path + id
        status: val.status
        history: val.history
        created: val.created
        modified: val.modified
    ret

  app.get("/intermediate/", (req, res) ->
    res.send getTasks('/intermediate/', intermediate)
  )
  app.get("/content/", (req, res) ->
    res.send getTasks('/content/', content)
  )
  app.get("/assembled/", (req, res) ->
    res.send getTasks('/assembled/', assembled)
  )
  app.get("/resource/", (req, res) ->
    res.send getTasks('/resource/', resources)
  )

  # Util function that either renders the promise or a 404
  renderObj = (res, name, table, index) ->
    if table[index]?
      table[index].send(res)
    else
      console.log "Problem Requesting #{name}=#{index}"
      res.send 404

  app.get("/intermediate/:id([0-9]+)", (req, res) ->
    renderObj res, 'intermediate', intermediate, req.params.id
  )
  app.get("/intermediate/:id([0-9]+).json", (req, res) ->
    res.send intermediate[req.params.id]
  )
  app.get("/assembled/:id([0-9]+)", (req, res) ->
    renderObj res, 'assembled', assembled, req.params.id
  )
  app.get("/resource/:id([0-9]+)", (req, res) ->
    renderObj res, 'resource', resources, req.params.id
  )
  app.get("/content/:id([0-9]+)", (req, res) ->
    renderObj res, 'content', content, req.params.id
  )
  app.get("/content/:id([0-9]+).pdf", (req, res) ->
    renderObj res, 'pdf', pdfs, req.params.id
  )

  # Internal
  app.post("/intermediate/:id([0-9]+)", (req, res) ->
    id = req.params.id
    intermediate[id].finish(req.body.contents, 'text/html; charset=utf-8')

    #content[id] = new Promise()
    fromUrl = "#{argv.u}/intermediate/#{id}"
    toUrl   = "#{argv.u}/content/#{id}"
    spawnGenerateStep(1, fromUrl, toUrl, id, content[id])
    res.send "OK"
  )
  app.post("/content/:id([0-9]+)", (req, res) ->
    id = req.params.id
    content[id].finish(req.body.contents, 'text/html; charset=utf-8')

    #assembled[id] = new Promise()
    fromUrl = "#{argv.u}/content/#{id}"
    toUrl   = "#{argv.u}/assembled/#{id}"
    spawnGenerateStep(3, fromUrl, toUrl, id, assembled[id])
    res.send "OK"
  )
  app.post("/assembled/:id([0-9]+)", (req, res) ->
    id = req.params.id
    assembled[id].finish(req.body.contents, 'text/html; charset=utf-8')

    spawnGeneratePDF(id, pdfs[id])
    #spawnGenerateEPUB(id, epubs[id])

    #toUrl   = "#{argv.u}/content/#{id}.pdf"
    #spawnGenerateStep('-epub', fromUrl, toUrl, id, epubs[id])
    res.send "OK"
  )
  app.post("/content/:id([0-9]+).pdf", (req, res) ->
    id = req.params.id
    pdfs[id].finish(unescape(req.body.contents), 'application/pdf')
    res.send "OK"
  )
  app.post("/svg-to-png", (req, res) ->
    svg = req.body.contents
    id = resources.length
    resource = new Promise()
    resource.svg = svg
    resources.push resource
    spawnConvertSVGIfNeeded()
    if not resources[id]
      console.error "AKSJHDASKJHDF"
    console.log "Sending back /resource/#{id}"
    res.send "/resource/#{id}"
  )

  # Traditional request to / redirects to index :)
  app.get('/', (req, res) ->
    res.redirect('index')
  )

  #### Start the server ####

  app.listen(argv.p, argv.o if argv.o)
  # When server is listening emit a ready event.
  app.emit "ready"
  console.log("Server listening in mode: #{app.settings.env}")

  # Return app when called, so that it can be watched for events and shutdown with .close() externally.
  app
