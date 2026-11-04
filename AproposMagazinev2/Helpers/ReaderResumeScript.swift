import Foundation

/// No window scroll or untrusted selector/id injection: native code owns the
/// outer scroll view. Both operations check this document's generated nonce.
enum ReaderResumeScript {
    static let source = #"""
    (function () {
      'use strict';
      var documentID = document.querySelector('meta[name="apropos-document"]')?.content;
      if (!documentID) return;
      function current(id) { return id === documentID && document.querySelector('meta[name="apropos-document"]')?.content === documentID; }
      function blocks() {
        var selector = 'p,h1,h2,h3,h4,h5,h6,blockquote,ul,ol';
        var candidates = document.querySelectorAll(selector), result = [];
        for (var i = 0; i < Math.min(candidates.length, 4000) && result.length < 1200; i++) {
          var e = candidates[i];
          if (e.closest('figure,figcaption,.apropos-image-credit,.apropos-offline-media,.w-embed,[data-apropos-reveal-exclude]') ||
              e.querySelector('img,picture,video,audio,iframe,embed,object,svg,canvas,.apropos-offline-media') ||
              (e.parentElement && e.parentElement.closest(selector)) || !e.textContent.trim()) continue;
          result.push(e);
        }
        return result;
      }
      function fingerprint(e) {
        var text = e.textContent.replace(/\s+/g, ' ').trim();
        if (text.length > 65536) return null;
        var hash = 2166136261;
        for (var i = 0; i < text.length; i++) hash = Math.imul(hash ^ text.charCodeAt(i), 16777619);
        return (hash >>> 0).toString(16).padStart(8, '0');
      }
      function top(e) {
        var value = 0, depth = 0;
        while (e && depth++ < 128) { value += e.offsetTop || 0; e = e.offsetParent; }
        return e || !Number.isFinite(value) ? null : value;
      }
      window.aproposReaderResume = {
        capture: function (id, viewportTop, viewportBottom) {
          if (!current(id) || !Number.isFinite(viewportTop) || !Number.isFinite(viewportBottom) || viewportTop < 0 || viewportBottom <= viewportTop) return null;
          var list = blocks(), index = -1;
          for (var i = 0; i < list.length; i++) {
            var y = top(list[i]);
            if (y !== null && y <= viewportTop + 24) index = i;
            else break;
          }
          if (index < 0 || !list[index].offsetHeight) return null;
          var signature = fingerprint(list[index]);
          return signature ? {documentID:documentID,index:index,fingerprint:signature} : null;
        },
        resolve: function (id, index, signature) {
          if (!current(id) || !Number.isInteger(index) || index < 0 || index >= 1200 || !/^[a-f0-9]{8}$/.test(signature)) return null;
          var e = blocks()[index];
          if (!e || fingerprint(e) !== signature || !e.offsetHeight) return null;
          var y = top(e);
          return y === null ? null : {documentID:documentID,top:y};
        }
      };
    })();
    """#
}
