/* =================================
    Javascript injector!
   =================================
 */
$().ready(function() {
    
    var idCounter = 0;
    
    $('*[data-script]').each(function() {
      try {
        $el = $(this);
        
        // If this is a media element then remove all children (they'll be replaced by this script)
        if ($el.hasClass('media')) {
          $el.contents().remove();
        }

        var id = $el.attr('id');
        if (!id) {
          id = 'interactive-auto-' + idCounter++;
          $el.attr('id', id);
        }

        var scriptCode = $el.attr('data-script');
        // We don't need the script anymore so remove it
        $el.removeAttr('data-script');
        
        var input = $el.attr('data-input') || $el.parents('*[data-input]').attr('data-input');
        
        //XSLT puts in a space right before a newline and this screws up CSV parsing
        // So, replace ' \n' with just '\n'
        if (input) {
          input = input.replace(' \n', '\n');
        }
        
        
        var config = {
          input: input,
          contextSelector: '#' + id,
          _id: id,
        };
        var sandboxTop = "(function(window, config, __element) { config.context = __element; ";
        var sandboxBottom = "}) ({d3: window.d3, Tangle: window.Tangle}, " + JSON.stringify(config) + ", $('#" + id + "')[0] );";
  
        var stringToEval = sandboxTop + scriptCode + sandboxBottom;
        eval(stringToEval);    
      } catch(e) {
        // Log the error and keep on moving
        console.error(e);
      }
    });
    // Since we're done processing, remove all the data-input attributes as well
    $('*[data-input]').removeAttr('data-input');
});