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
id          = system.args[6]


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
  if status != 'success'
    console.error "File not FOUND!!"
    phantom.exit(1)

  loadScript = (path) ->
    if page.injectJs(path)
    else
      console.error "Could not find #{path}"
      phantom.exit(1)
  
  loadScript(programDir + '/static/lib/jquery-latest.js')
  ###
  loadScript(programDir + '/lib/d3.js')
  loadScript(programDir + '/lib/mathjax/MathJax.js')
  loadScript(programDir + '/lib/Tangle/Tangle.js')
  loadScript(programDir + '/lib/Tangle/TangleKit/mootools.js')
  loadScript(programDir + '/lib/Tangle/TangleKit/sprintf.js')
  loadScript(programDir + '/lib/Tangle/TangleKit/BVTouchable.js')
  loadScript(programDir + '/lib/Tangle/TangleKit/TangleKit.js')
  loadScript(programDir + '/lib/dom-to-xhtml.js')
  loadScript(programDir + '/lib/rasterize.js')
  loadScript(programDir + '/lib/injector.js')
  ###

  needToKeepWaiting = page.evaluate((outputUrl, depositUrl, LOCALHOST, id) ->

    loadScript = (src) ->
      $script = $('<script></script>')
      $script.attr('type', 'text/javascript')
      $script.attr('src', src)
      $('body').append $script
    #loadScript "#{LOCALHOST}/lib/jquery-latest.js"
    #loadScript "#{LOCALHOST}/lib/mathjax/MathJax.js?config=MML_HTMLorMML-full"

    # Can't load MathJax using jQuery either. It doesn't process the entire document.
    script = document.createElement('script')
    script.setAttribute('src', "#{LOCALHOST}/lib/mathjax/MathJax.js?config=TeX-AMS-MML_SVG-full")
    document.getElementsByTagName('body')[0].appendChild(script)
    
    loadScript "#{LOCALHOST}/lib/d3.js"
    loadScript "#{LOCALHOST}/lib/Tangle/Tangle.js"
    loadScript "#{LOCALHOST}/lib/Tangle/TangleKit/mootools.js"
    loadScript "#{LOCALHOST}/lib/Tangle/TangleKit/sprintf.js"
    loadScript "#{LOCALHOST}/lib/Tangle/TangleKit/BVTouchable.js"
    loadScript "#{LOCALHOST}/lib/Tangle/TangleKit/TangleKit.js"
    loadScript "#{LOCALHOST}/lib/dom-to-xhtml.js"
    loadScript "#{LOCALHOST}/lib/rasterize.js"
    loadScript "#{LOCALHOST}/lib/injector.js"

    callback = () ->
    
      # We need to convert all the canvas elements and images with dataURI's to images
      rasterizer = new (window.Rasterize)()
      rasterizer.convert()
      
      # Rewrite the URLs for XIncluded documents and begin processing them
      # Given the <base> element in <head> we can resolve relative URLs
      base = $('head meta[href]').attr('href')
      baseHref = base.replace(/\/[^\/]*$/, '')
      baseDomain = base.split('/')[0] + '//' + base.split('/')[2] # ie http://cnx.org:1234/

      toAbsoluteUrl = (href) ->
        # TODO: Fix up ".." in relative paths
        if href.charAt(0) == '#'
          # It's an internal link. No change necessary
          href
        else if href.search(/^https?:\/\//) >= 0
          # It's already absolute
          href
        else if href.search(/^\//) >= 0
          # It starts with a "/"
          baseDomain + href
        else
          # It's a relative path
          baseHref + href
      
      # Make URLs absolute instead of relative
      $('a[href]').each () ->
        $a = $(@)
        href = toAbsoluteUrl($a.attr('href'))
        $a.attr('href', href)

      $('img[src]').each () ->
        $a = $(@)
        href = toAbsoluteUrl($a.attr('src'))
        $a.attr('src', href)
      
      xincludes = $('a[href].xinclude')
      leftToProcess = xincludes.length
      console.log "Remote deposit count #{leftToProcess}"
      
      serializeHtml = (callback) ->
        # Hack to serialize out the HTML (sent to the console)
        console.log 'Serializing (X)HTML back out from WebKit...'
        $('script').remove()
        xhtmlAry = []
        xhtmlAry.push '<html xmlns="http://www.w3.org/1999/xhtml">'
        # Keep the base element in there
        xhtmlAry.push '<head>'
        window.dom2xhtml.serialize($('head meta')[0], xhtmlAry)
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
            alert "Submit Failed" # Problem.
          .done (text) ->
            console.log "Sent XHTML back to server with response: #{text}"
            alert '' # All OK to close up

      if leftToProcess == 0
        serializeHtml()
      
      xincludes.each () ->
        $a = $(@)
        href = $a.attr('href')
        # PHIL href = href + "/index_auto_generated.cnxml"
          
        console.log "Depositing #{href} via #{depositUrl} wrt #{id}"
        
        # Perform the ajax call
        params = { url: href, original: id }
        options =
          url: depositUrl
          type: 'POST'
          data: params
        $.ajax(options)
          .fail () ->
            console.error "Problem Converting #{href}"
          .done (text) ->
            console.log "Converted #{href} to #{text}"
            $a.attr('data-url', href)
            $a.attr('href', text)
          .always () ->
            leftToProcess--
            if leftToProcess == 0
              serializeHtml()


    # Configure MathJax
    console.log "Waiting to finish processing math..."

    mathJaxHack = () ->
      console.error "Could not load MathJax" if not window.MathJax
      try # Fails if MathJax isn't loaded into the page. So far, it's up to the HTML file to find/include MathJax
        MathJax.Hub.Queue () ->
          console.log "Finished Processing math!  "
          $('#MathJax_Message').remove() # This function gets called before MathJax removes the "Typesetting 100%" message
          # Copy all the SVG glyphs to multiple SVG elmeents
          # See http://www.w3.org/TR/SVG11/struct.html#UseElement
          $('#MathJax_SVG_Hidden').remove()
          $uses = $('.MathJax_SVG svg use')
          $uses.each () ->
            $use = $(@)
            x = $use.attr('x') or 0
            y = $use.attr('y') or 0
            transform = $use.attr('transform') or ''
            $g = $("<g transform='#{transform} translate(#{x}, #{y})'></g>")
            $g.append $($use.attr('href'))[0].cloneNode(true)
            $use.replaceWith $g
          callback()
      catch e
        console.error "ERROR Happened"
        console.error e
        alert e
    setTimeout mathJaxHack, 10000
  , outputUrl, depositUrl, LOCALHOST, id)