system = require('system')
fs = require('fs')
page = require("webpage").create()

page.settings.localToRemoteUrlAccessEnabled = true
page.settings.ignoreSslErrors = true

page.onConsoleMessage = (msg, line, source) ->
  console.log "console> " + msg # + " @ line: " + line

if system.args.length < 3
  console.error "This program takes exactly 2 arguments:"
  console.error "The absolute path to this directory (I know, it's annoying but I need it to load the jquery, mathjax, and the like)"
  console.error "URL to the HTML file"
  console.error "URL to post the output (X)HTML file"
  console.error "URL to submit xincluded URLs to (and translate)"
  phantom.exit 1

programDir  = system.args[1]

inputUrl    = system.args[2]
outputUrl   = system.args[3]
depositUrl  = system.args[4]
LOCALHOST   = system.args[5]


page.onConsoleMessage = (message, url, lineNumber) ->
  console.error message


page.onError = (msg, trace) ->
  console.error(msg)
  trace.forEach (item) ->
    console.error('  ', item.file, ':', item.line);

  phantom.exit(1)

#if (!/^file:\/\/|http(s?):\/\//.test(appLocation)) {
#    appLocation = 'file:///' + fs.absolute(appLocation).replace(/\\/g, '/');
#}


console.error "Opening page at: #{inputUrl}"

page.onAlert = (msg) ->
  if msg
    phantom.exit(1)
  else
    console.error "All good, closing PhantomJS"
    phantom.exit(0)

page.open encodeURI(inputUrl), (status) ->
  console.log "Hello. Status is [#{status}]"
  if status != 'success'
    console.error "File not FOUND!!"
    phantom.exit(1)

  loadScript = (path) ->
    if page.injectJs(path)
    else
      console.error "Could not find #{path}"
      phantom.exit(1)
  
  loadScript(programDir + '/static/lib/jquery-latest.js')

  needToKeepWaiting = page.evaluate((outputUrl, depositUrl, LOCALHOST) ->

    loadScript = (src) ->
      $script = $('<script></script>')
      $script.attr('type', 'text/javascript')
      $script.attr('src', src)
      $('body').append $script

    loadScript "#{LOCALHOST}/lib/dom-to-xhtml.js"

    serializeHtml = (callback) ->
      # Hack to serialize out the HTML (sent to the console)
      console.log 'Serializing (X)HTML back out from WebKit...'
      $('script').remove()
      xhtmlAry = []
      xhtmlAry.push '<html xmlns="http://www.w3.org/1999/xhtml">'
      # Keep the base element in there
      xhtmlAry.push '<head>'
      window.dom2xhtml.serialize($('head base')[0], xhtmlAry)
      xhtmlAry.push '</head>'
      window.dom2xhtml.serialize($('body')[0], xhtmlAry)
      xhtmlAry.push '</html>'

      console.log 'Submitting (X)HTML back to the server...'
      params =
        contents: xhtmlAry.join('')
      config =
        url: outputUrl
        type: 'POST'
        data : params
      $.ajax(config)
        .fail () ->
          alert "Submit Failed on POST to #{outputUrl}" # Problem.
        .done (text) ->
          console.log "Sent XHTML back to server with response: #{text}"
          alert '' # All OK to close up

    # Make URLs absolute instead of relative
    xincludes = $('a[href].xinclude')
    leftToProcess = xincludes.length

    if leftToProcess == 0
      serializeHtml()

    xincludes.each () ->
      $a = $(@)
      href = $a.attr('href')
      
      # Include the file at this position (maybe put in the contents of the element)
      retries = 10
      tryAjax = () ->
        config =
          url: href
          type: 'GET'
        $.ajax(config)
          .fail () ->
            # Wait and repeat (depending on the status code)
            console.log "Retrying #{retries} GET #{href} in 30 seconds"
            if retries-- > 0
              setTimeout tryAjax, 30000
            else
              console.error "Gave up retrying to GET #{href}. Continuing on"
              leftToProcess--
              if leftToProcess == 0
                serializeHtml()
          .done (text) ->
            console.log "GET #{href} Succeeded. Injecting..."
            newElement = $(text)
            $a.replaceWith newElement.contents()
            
            if not $a.hasClass('autogenerated')
              newTitle = newElement.children('.title').first()
              newTitle.contents().remove()
              $a.contents().appendTo newTitle

            leftToProcess--
            if leftToProcess == 0
              serializeHtml()
      tryAjax()

  , outputUrl, depositUrl, LOCALHOST)