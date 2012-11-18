# Set export objects for node and coffee to a function that generates a sfw server.
module.exports = exports = (argv) ->

  #### Dependencies ####
  # anything not in the standard library is included in the repo, or
  # can be installed with an:
  #     npm install
  express     = require('express')
  path        = require('path')
  url         = require('url')
  fs          = require('fs') # Just to load jQuery

  Promise     = require('./util').Promise
  spawnGeneratePDF = require('./util').spawnGeneratePDF

  # Create the main application object, app.
  app = express.createServer()

  # defaultargs.coffee exports a function that takes the argv object that is passed in and then does its
  # best to supply sane defaults for any arguments that are missing.
  argv = require('./defaultargs')(argv)

  # In-memory "database" of all the Promises to make PDFs
  PDFS = []

  #### Express configuration ####
  # Set up all the standard express server options,
  # including hbs to use handlebars/mustache templates
  # saved with a .html extension, and no layout.
  app.configure( ->
    app.set('view options', layout: false)
    app.use(express.bodyParser())
    app.use(express.methodOverride())
    app.use(app.router)
    app.use(express.static(path.join(__dirname, '..', 'node_modules')))
    app.use(express.static(path.join(__dirname, '..', 'static')))
  )

  ##### Set up standard environments. #####
  # In dev mode turn on console.log debugging as well as showing the stack on err.
  app.configure('development', ->
    app.use(express.errorHandler({ dumpExceptions: true, showStack: true }))
    argv.debug = console? and true
  )
  # Swallow errors when in production.
  app.configure('production', ->
    app.use(express.errorHandler())
  )

  # Show all of the options a server is using.
  console.log argv if argv.debug




  #### Routes ####

  # The API should be simple:
  #
  # * `POST /pdfs?url=http://somewhere/collection.zip` responds with `/pdfs/[id]`
  # * `GET /pdfs/[id]` either returns a 202/404 with a JSON Promise or
  # * `GET /pdfs/[id]` returns a 200 with the PDF
  #
  # For admin/monitoring:
  # * `GET /pdfs` returns a list of the most recent PDF tasks
  # * `POST /pdfs/[id]/kill` kills that task

  # Someone would like us to generate a PDF!
  app.post('/pdfs', (req, res, next) ->
    url = req.param('url')
    style = req.param('style', 'ccap-physics')

    promise = new Promise()
    promise.url = url
    id = PDFS.length
    PDFS.push(promise)

    spawnGeneratePDF(promise, argv.g, url, style)
    res.send "/pdfs/#{id}"
  )

  # Returns either the PDF or a 202/404
  # with a JSON body representing the status
  # (The Promise.send handles that logic)
  app.get('/pdfs/:id([0-9]+)', (req, res) ->
    # Let the promise decide how to respond
    promise = PDFS[req.params.id]
    promise.send(res)
  )

  # For debugging always send back the Promise.toString()
  app.get('/pdfs/:id([0-9]+).json', (req, res) ->
    # Let the promise decide how to respond
    promise = PDFS[req.params.id]
    res.send JSON.parse(promise.toString())
  )

  # Returns a list of all the PDFs.
  # __Note:__ This could just return all the id's
  app.get('/pdfs', (req, res) ->
    # Get the toString() versions of all the promises
    res.send (JSON.parse(pdf.toString()) for pdf in PDFS)
  )

  # Kills a running PDF process
  # TODO: Add some authentication
  app.all("/pdfs/:id([0-9]+)/kill", (req, res) ->
    PDFS[req.params.id].fail('User Killed this task')
  )


  # Traditional request to / redirects to the admin page
  app.get('/', (req, res) ->
    res.redirect('admin.html')
  )

  #### Start the server ####

  app.listen(argv.p, argv.o if argv.o)
  # When server is listening emit a ready event.
  app.emit 'ready'
  console.log("Server listening in mode: #{app.settings.env}")

  # Return app when called, so that it can be watched for events and shutdown with .close() externally.
  app
