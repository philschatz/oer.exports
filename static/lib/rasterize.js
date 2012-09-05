
/*
What does this file do?
-----------------------

It converts canvas elements to binary "images" that can be "chunked" out for EPUB and updates the elements in the DOM.
It also does the same thing with images that have a data URI.
*/

(function() {
  var Rasterize;

  Rasterize = (function() {

    function Rasterize(config) {
      var defaultConfig;
      if (config == null) config = {};
      defaultConfig = {
        outputMimeType: 'image/png'
      };
      this.config = $.extend(defaultConfig, config);
    }

    /* Returns a string of the new CSS
    */

    Rasterize.prototype.convert = function(rootNode) {
      var config, filesCounter, filesMap;
      if (rootNode == null) rootNode = $('html');
      config = this.config;
      filesCounter = 0;
      filesMap = {};
      rootNode.find('canvas').each(function() {
        var $canvas, $img, data;
        $canvas = $(this);
        data = $canvas[0].toDataURL(config.mimeType);
        $img = $('<img></img>');
        $img.attr('src', data);
        return $canvas.replaceWith($img);
      });
      console.log("Found " + (rootNode.find('img[src]').length) + " images!");
      rootNode.find('img[src]').each(function() {
        var $img, fileName, src;
        $img = $(this);
        src = $img.attr('src');
        if (src.indexOf('data:') === 0) {
          fileName = "auto-from-dataURI-" + (filesCounter++) + ".png";
          filesMap[fileName] = src;
          return $img.attr('src', fileName);
        }
      });
      return filesMap;
    };

    return Rasterize;

  })();

  if (typeof module !== "undefined" && module !== null) {
    module.exports = Rasterize;
  } else if (typeof window !== "undefined" && window !== null) {
    window.Rasterize = Rasterize;
  }

}).call(this);
