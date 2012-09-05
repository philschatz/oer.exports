(function() {
  var LOCALHOST, depositUrl, fs, inputUrl, outputUrl, page, programDir, system;

  system = require('system');

  fs = require('fs');

  page = require("webpage").create();

  page.settings.localToRemoteUrlAccessEnabled = true;

  page.settings.ignoreSslErrors = true;

  page.onConsoleMessage = function(msg, line, source) {
    return console.log("console> " + msg);
  };

  if (system.args.length < 3) {
    console.error("This program takes exactly 2 arguments:");
    console.error("The absolute path to this directory (I know, it's annoying but I need it to load the jquery, mathjax, and the like)");
    console.error("URL to the HTML file");
    console.error("URL to post the output (X)HTML file");
    console.error("URL to submit xincluded URLs to (and translate)");
    phantom.exit(1);
  }

  programDir = system.args[1];

  inputUrl = system.args[2];

  outputUrl = system.args[3];

  depositUrl = system.args[4];

  LOCALHOST = system.args[5];

  page.onConsoleMessage = function(message, url, lineNumber) {
    return console.error(message);
  };

  page.onError = function(msg, trace) {
    console.error(msg);
    trace.forEach(function(item) {
      return console.error('  ', item.file, ':', item.line);
    });
    return phantom.exit(1);
  };

  console.error("Opening page at: " + inputUrl);

  page.onAlert = function(msg) {
    if (msg) {
      return phantom.exit(1);
    } else {
      console.error("All good, closing PhantomJS");
      return phantom.exit(0);
    }
  };

  page.open(encodeURI(inputUrl), function(status) {
    var loadScript, needToKeepWaiting;
    console.log("Hello. Status is [" + status + "]");
    if (status !== 'success') {
      console.error("File not FOUND!!");
      phantom.exit(1);
    }
    loadScript = function(path) {
      if (page.injectJs(path)) {} else {
        console.error("Could not find " + path);
        return phantom.exit(1);
      }
    };
    loadScript(programDir + '/static/lib/jquery-latest.js');
    return needToKeepWaiting = page.evaluate(function(outputUrl, depositUrl, LOCALHOST) {
      var callback, mathJaxHack;
      loadScript = function(src) {
        var $script;
        $script = $('<script></script>');
        $script.attr('type', 'text/javascript');
        $script.attr('src', src);
        return $('body').append($script);
      };
      callback = function() {
        var leftToProcess, serializeHtml, xincludes;
        serializeHtml = function(callback) {
          var config, params, xhtmlAry;
          console.log('Serializing (X)HTML back out from WebKit...');
          $('script').remove();
          xhtmlAry = [];
          xhtmlAry.push('<html xmlns="http://www.w3.org/1999/xhtml">');
          xhtmlAry.push('<head>');
          window.dom2xhtml.serialize($('head base')[0], xhtmlAry);
          xhtmlAry.push('</head>');
          window.dom2xhtml.serialize($('body')[0], xhtmlAry);
          xhtmlAry.push('</html>');
          console.log('Submitting (X)HTML back to the server...');
          params = {
            contents: xhtmlAry.join('')
          };
          config = {
            url: outputUrl,
            type: 'POST',
            data: params
          };
          return $.ajax(config).fail(function() {
            return alert("Submit Failed");
          }).done(function(text) {
            console.log("Sent XHTML back to server with response: " + text);
            return alert('');
          });
        };
        xincludes = $('a[href].xinclude');
        leftToProcess = xincludes.length;
        if (leftToProcess === 0) serializeHtml();
        return xincludes.each(function() {
          var $a, href, tryAjax;
          $a = $(this);
          href = $a.attr('href');
          tryAjax = function() {
            var config;
            config = {
              url: href,
              type: 'GET'
            };
            return $.ajax(config).fail(function() {
              console.log("Retrying GET " + href + " in 30 seconds");
              return setTimeout(tryAjax, 30000);
            }).done(function(text) {
              var newElement;
              console.log("GET " + href + " Succeeded. Injecting...");
              newElement = $(text);
              $a.replaceWith(newElement.contents());
              leftToProcess--;
              if (leftToProcess === 0) return serializeHtml();
            });
          };
          return tryAjax();
        });
      };
      console.log("Waiting to finish processing math...");
      mathJaxHack = function() {
        if (!window.MathJax) console.error("Could not load MathJax");
        try {
          return MathJax.Hub.Queue(function() {
            console.log("Finished Processing math!  ");
            $('#MathJax_Message').remove();
            return callback();
          });
        } catch (e) {
          console.error("ERROR Happened");
          console.error(e);
          return alert(e);
        }
      };
      return setTimeout(mathJaxHack, 10000);
    }, outputUrl, depositUrl, LOCALHOST);
  });

}).call(this);
