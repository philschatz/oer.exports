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
  # Authentication machinery
  passport    = new (require('passport')).Passport()
  OpenIDstrat = require('passport-openid').Strategy


  #### State ####
  # Stores in-memory state
  class Promise
    constructor: () ->
      @start = new Date()
      @history = []
      @isProcessing = true
      @data = null
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
      @history.push msg
    fail: () ->
      @isProcessing = false
      @data = null
    finish: (@data, @mimeType='text/html') ->
      @isProcessing = false
  
  intermediate = {}
  content = {}
  assembled = {}
  globalLookups = {}
  lookups = {}
  resources = []
  resourcesQueueIndex = 0
  resourcesProcessing = false
  hashId = 0


  #### Spawns ####
  env = { }

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
  
  spawnConvertSVGIfNeeded = () ->
    if resourcesQueueIndex < resources.length and not resourcesProcessing
      resourcesProcessing = true
      setTimeout(() ->
        console.log ("id=SVG Starting resourceId=#{resourcesQueueIndex}")
        child = spawn('rsvg-convert', [ "--dpi-x=#{SVG_TO_PNG_DPI}", "--dpi-y=#{SVG_TO_PNG_DPI}" ], env)
        chunks = []
        chunkLen = 0
        child.stdin.write(resources[resourcesQueueIndex].svg)
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
          resources[resourcesQueueIndex].finish(png, 'image/png')
          resourcesQueueIndex++
          spawnConvertSVGIfNeeded()
        child.stderr.on 'data', childLogger(true, 'svg2png')
      , 10)
    
  
  spawnGenerateStep = (step, fromUrl, toUrl, id, promise) ->
    console.log "Spawning step#{step}.sh [#{fromUrl}, #{toUrl}, #{id}, #{argv.u}/deposit, #{argv.u}]"
    child = spawn("step#{step}.sh", [fromUrl, toUrl, id, "#{argv.u}/deposit", "#{argv.u}"], env)
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
  app.post('/deposit', (req, res, next) ->
    href = req.body.url
    originalId = req.body.original
    console.log "Received deposit request for #{href} with originalId=#{originalId}"
    id = addToGlobal(href)
    lookups[id] = {}
    if originalId?
      lookups[originalId][href] = id
    # Disabled "/source" for local content: spawnGenerateStep(0, href + '/source', "#{argv.u}/intermediate/#{id}", id)

    # Create all the promises (to be filled out later)
    intermediate[id] = new Promise()
    content[id] = new Promise()
    assembled[id] = new Promise()

    spawnGenerateStep(0, href, "#{argv.u}/intermediate/#{id}", id, intermediate[id])
    #res.send "#{argv.u}/content/#{id}"
    res.send "#{id}"
  )

  # For debugging
  app.get("/intermediate/", (req, res) ->
    keys = (key for key of assembled)
    res.send keys
  )
  app.get("/content/", (req, res) ->
    keys = (key for key of content)
    res.send keys
  )
  app.get("/lookups/", (req, res) ->
    res.send globalLookups
  )
  app.get("/lookups2/", (req, res) ->
    res.send lookups
  )
  app.get("/assembled/", (req, res) ->
    keys = (key for key of assembled)
    res.send keys
  )
  app.get("/resource/", (req, res) ->
    keys = (key for key of resources)
    res.send keys
  )

  app.get("/intermediate/:id([0-9]+)", (req, res) ->
    intermediate[req.params.id].send(res)
  )
  app.get("/assembled/:id([0-9]+)", (req, res) ->
    assembled[req.params.id].send(res)
  )
  app.get("/resource/:id([0-9]+)", (req, res) ->
    resources[req.params.id].send(res)
  )
  app.get("/content/:id([0-9]+)", (req, res) ->
    content[req.params.id].send(res)
  )

  # Internal
  app.post("/intermediate/:id([0-9]+)", (req, res) ->
    id = req.params.id
    intermediate[id].finish(req.body.contents, 'text/html')
    
    #content[id] = new Promise()
    fromUrl = "#{argv.u}/intermediate/#{id}"
    toUrl   = "#{argv.u}/content/#{id}"
    spawnGenerateStep(1, fromUrl, toUrl, id, content[id])
    res.send "OK"
  )
  app.post("/assembled/:id([0-9]+)", (req, res) ->
    assembled[req.params.id].finish(req.body.contents, 'text/html')
    res.send "OK"
  )
  app.post("/content/:id([0-9]+)", (req, res) ->
    id = req.params.id
    content[id].finish(req.body.contents, 'text/html')

    #assembled[id] = new Promise()
    fromUrl = "#{argv.u}/content/#{id}"
    toUrl   = "#{argv.u}/assembled/#{id}"
    spawnGenerateStep(3, fromUrl, toUrl, id, assembled[id])
    res.send "OK"
  )
  app.post("/svg-to-png", (req, res) ->
    svg = req.body.contents
    id = resources.length
    resource = new Promise()
    resource.svg = svg
    resources.push resource
    spawnConvertSVGIfNeeded()
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
