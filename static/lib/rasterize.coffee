###
What does this file do?
-----------------------

It converts canvas elements to binary "images" that can be "chunked" out for EPUB and updates the elements in the DOM.
It also does the same thing with images that have a data URI.
###


class Rasterize
  constructor: (config = {}) ->
    defaultConfig =
      outputMimeType: 'image/png'
      
    @config = $.extend(defaultConfig, config)

  ### Returns a string of the new CSS ###
  convert: (rootNode=$('html')) ->
    config = @config # Things like filters change @ so just use a local variable

    filesCounter = 0
    filesMap = {}
    rootNode.find('canvas').each () ->
      $canvas = $(@)
      data = $canvas[0].toDataURL(config.mimeType)
      $img = $('<img></img>')
      $img.attr('src', data)
      $canvas.replaceWith $img


    console.log "Found #{rootNode.find('img[src]').length} images!"
    rootNode.find('img[src]').each () ->
      $img = $(@)
      src = $img.attr('src')
      if src.indexOf('data:') == 0
        fileName = "auto-from-dataURI-#{filesCounter++}.png"
        filesMap[fileName] = src
        $img.attr('src', fileName)
    filesMap  

if module?
  module.exports = Rasterize
else if window?
  window.Rasterize = Rasterize
