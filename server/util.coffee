# A couple of functions and classes that are useful outside the webserver context
# or useful for more than one webserver.

# require dependencies
EventEmitter = require('events').EventEmitter
spawn       = require('child_process').spawn
path        = require('path')


# # Promise
# Stores the status of an asynchronous Task
#
# The `Promise` is updated when the spawned process sends to `stderr`
# The `Promise` fails when the spawned process completes without sending
# anything to `stdout`.
# The `Promise` is sent back as the body of a 202 response when processing is complete.
#
# The spawned process directly manipulates the `Promise` and the `Promise`
# has the logic to generate a correct HTTP Response.
module.exports.Promise = class Promise extends EventEmitter
  # Private variables and functions go here
  MAX_HISTORY_SIZE = 50
  FIELDS_TO_REMOVE = [ 'pid', 'data' ] # Maybe include 'status'

  constructor: () ->
    @status = 'WORKING'
    @created = new Date()
    @history = []
    @data = null
  # Used to serialize a Promise through the web
  # Filters out private fields
  # (or ones that can't be serialized)
  toString: () ->
    JSON.stringify @, (key, value) ->
      # Skip the pid and payload so we can serialize
      return value if key not in FIELDS_TO_REMOVE

  # Send either the data (if available), or a HTTP Status with this JSON
  # Cases (based on `status`:
  #
  # * `WORKING`: return a 202 and the JSON Promise (for admin/debugging, progress bars)
  # * `FINISHED`: `data` is not null so return a 200 with the payload
  # * `FAILED`: return a 404 with the JSON promise (optional. could just be generic 404)
  #
  # `res` is a HTTP response object
  send: (res) ->
    switch @status
      when 'WORKING'
        # Use @toString so the pid is removed and reparse so we send the right content type
        res.status(202).send JSON.parse(@toString())
      when 'FINISHED'
        res.header('Content-Type', @mimeType)
        res.send @data
      else
        # Use @toString so the pid is removed and reparse so we send the right content type
        res.status(404).send JSON.parse(@toString())

  # Updates a promise while `WORKING`.
  # Adds a message to the history and updates the modified time
  update: (msg=null) ->
    console.warn "BUG: Promise.update called but status=#{@status}" if @status != 'WORKING'
    @modified = new Date()
    return if msg is null # Just update the date
    @history.push msg
    # Clean up the history so it doesn't get too unwieldy
    if @history.length > MAX_HISTORY_SIZE
      @history.splice(0,1)
    # Matches the EventEmitter in case anyone is listening
    @emit('update', msg)

  # Causes the promise to fail.
  # From now on the URL will return a 404 until someone restarts the task
  fail: (msg) ->
    console.warn "BUG: Promise.fail called but status=#{@status}" if @status != 'WORKING'
    @update msg
    @status = 'FAILED'
    @data = null
    # Send the spawned process a SIGTERM signal
    # in case the spawned process didn't cause the call to fail() (ie "Kill Button")
    @pid.kill() if @pid
    @emit('fail')
  # Causes the promise to complete.
  # From now on the URL will return a 200 until someone restarts the task
  finish: (@data, @mimeType='text/html; charset=utf-8') ->
    console.warn "BUG: Promise.finish called but status=#{@status}" if @status != 'WORKING'
    @update 'Finished Processing'
    @status = 'FINISHED'
    @emit('finish', @data, @mimeType)


#### Spawns ####
# A spawned task attaches itself to a `Promise` and by parsing IO from the child
# the promise is updated.

# The script that downloads a Zip (maybe from file://) performs some processing
# and writes progress updates to `stderr` and the PDF to `stdout`
PDFGEN_SCRIPT = path.join(__dirname, '..', 'generate-pdf.sh')

# Code that parses stderr and updates
# the progress when the line 'STATUS: ##%' is seen
childLogger = (promise) -> (data) ->
  lines = data.toString().split('\n')
  for line in lines
    if line.length > 1
      percent = /^STATUS: (\d+)%/.exec(line)
      if percent
        promise.progress.finished = parseInt(percent[1])
      else
        promise.update line

module.exports.spawnGeneratePDF = (promise, princePath, url, style) ->
  # Except for cwd the rest are environment variables PDFGEN_SCRIPT expects
  options =
    cwd: path.join(__dirname, '..')
    env:
      PRINCEXML_PATH: princePath
      URL: url
      STYLE: style

  console.log options.env
  child = spawn('sh', [ '-xv', PDFGEN_SCRIPT ], options)
  # Attach the process to the promise so we can kill it
  promise.pid = child

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

  child.stderr.on 'data', childLogger(promise)
  promise.progress = {finished: 0, total: 100}

