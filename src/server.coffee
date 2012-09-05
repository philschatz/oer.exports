# Set export objects for node and coffee to a function that generates a sfw server.
module.exports = exports = (argv) ->
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


  #### Spawns ####
  env = {}
  
  spawnGenerateStep = (step, fromUrl, toUrl, id) ->
    console.log "Spawning step#{step}.sh [#{fromUrl}, #{toUrl}, #{id}, #{argv.u}/deposit, #{argv.u}]"
    child = spawn("step#{step}.sh", [fromUrl, toUrl, id, "#{argv.u}/deposit", "#{argv.u}"], env)
    child.stdout.on 'data', (data) ->
      console.log("id=#{id}: #{data}");
    child.stderr.on 'data', (data) ->
      console.error("Error id=#{id}: #{data}");

  #### State ####
  # Stores in-memory state
  intermediate = {}
  content = {}
  assembly = {}
  hashId = 0


  # Create the main application object, app.
  app = express.createServer()

  # defaultargs.coffee exports a function that takes the argv object that is passed in and then does its
  # best to supply sane defaults for any arguments that are missing.
  argv = require('./defaultargs')(argv)
  
  newContentPromise = () ->
    id = hashId++
    #content[id] = {}
    id


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
    console.log "Received deposit request for #{href}"
    id = newContentPromise()
    spawnGenerateStep(0, href, "#{argv.u}/intermediate/#{id}", id)
    res.send "#{argv.u}/content/#{id}"
  )

  # For debugging
  app.get("/intermediate/", (req, res) ->
    keys = (key for key of assembly)
    res.send keys
  )
  app.get("/content/", (req, res) ->
    keys = (key for key of content)
    res.send keys
  )
  app.get("/assembled/", (req, res) ->
    keys = (key for key of assembly)
    res.send keys
  )

  app.get("/intermediate/:id([0-9]+)", (req, res) ->
    res.send intermediate[req.params.id]
  )
  app.get("/assembled/:id([0-9]+)", (req, res) ->
    res.send assembly[req.params.id]
  )
  app.get("/content/:id([0-9]+)", (req, res) ->
    res.send content[req.params.id].html
  )
  app.get("/content/:id([0-9]+).pdf", (req, res) ->
    res.send content[req.params.id].pdf
  )
  app.get("/content/:id([0-9]+).epub", (req, res) ->
    res.send content[req.params.id].epub
  )

  # Internal
  app.post("/intermediate/:id([0-9]+)", (req, res) ->
    id = req.params.id
    intermediate[id] = req.body.contents
    
    fromUrl = "#{argv.u}/intermediate/#{id}"
    toUrl   = "#{argv.u}/content/#{id}"
    spawnGenerateStep(1, fromUrl, toUrl, id)
    res.send "OK"
  )
  app.post("/assembled/:id([0-9]+)", (req, res) ->
    assembly[req.params.id] = req.body.contents
    res.send "OK"
  )
  app.post("/content/:id([0-9]+)", (req, res) ->
    id = req.params.id
    content[id] =
      html: req.body.contents

    fromUrl = "#{argv.u}/content/#{id}"
    toUrl   = "#{argv.u}/assembled/#{id}"
    spawnGenerateStep(3, fromUrl, toUrl, id)
    res.send "OK"
  )
  app.post("/content/:id([0-9]+).pdf", (req, res) ->
    content[req.params.id]['pdf'] = req.body.contents
    res.send "OK"
  )
  app.post("/content/:id([0-9]+).epub", (req, res) ->
    content[req.params.id]['epub'] = req.body.contents
    res.send "OK"
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
