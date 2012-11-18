# A couple of functions and classes that are useful outside the webserver context
# or useful for more than one webserver.

# require dependencies
EventEmitter = require('events').EventEmitter
spawn       = require('child_process').spawn
path        = require('path')

#### State ####
# Stores the status of an asynchronous Promise
#
# It's updated by the running task and knows how to send
# the finished document if processing completed.
module.exports.Promise = class Promise extends EventEmitter
  constructor: (prerequisite) ->
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
  toString: () ->
    JSON.stringify @, (key, value) ->
      # Skip the pid so we can serialize
      return value if 'pid' != key
  # Send either the data (if available), or a HTTP Status with this JSON
  send: (res) ->
    if @isProcessing
      # Use @toString so the pid is removed and reparse so we send the right content type
      res.status(202).send JSON.parse(@toString())
    else if @data
      res.header('Content-Type', @mimeType)
      res.send @data
    else
      # Use @toString so the pid is removed and reparse so we send the right content type
      res.status(404).send JSON.parse(@toString())
  update: (msg=null) ->
    @modified = new Date()
    return if msg is null
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
    @pid.kill() if @pid
  finish: (@data, @mimeType='text/html; charset=utf-8') ->
    @update "Generated file"
    @isProcessing = false
    @status = 'FINISHED'
    @emit('finish', @data, @mimeType)


#### Spawns ####

PDFGEN_SCRIPT = path.join(__dirname, '..', 'generate-pdf.sh')

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

  child = spawn('sh', [ PDFGEN_SCRIPT ], options)
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

