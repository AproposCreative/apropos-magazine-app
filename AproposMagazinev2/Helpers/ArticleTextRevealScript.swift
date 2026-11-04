import Foundation

/// Paragraph motion driven by the native reader's clipped viewport, rather than
/// the full-height, non-scrolling web view's own intersection/scroll coordinates.
enum ArticleTextRevealScript {
    static let source = #"""
    (function () {
        'use strict';
        if (window.aproposReaderReveal && window.aproposReaderReveal.teardown) {
            window.aproposReaderReveal.teardown();
        }

        var attribute = 'data-apropos-reader-motion';
        var proseSelector = 'p,h1,h2,h3,h4,h5,h6,blockquote,ul,ol';
        var excludedSelector = 'figure,figcaption,.apropos-image-credit,.apropos-offline-media,' +
            '[data-apropos-reveal-exclude],.w-embed';
        var mediaSelector = 'img,picture,video,audio,iframe,embed,object,svg,canvas,.apropos-offline-media';
        var maximumBlocks = 1200;
        var maximumCandidates = 4000;
        var records = [];
        var known = new Map();
        var activeAnimations = new Set();
        var stopped = false;
        var frame = null;
        var cleanupTimer = null;
        var viewport = null;
        var nativeReduceMotion = false;
        var needsScan = true;
        var needsMeasurement = true;
        var style = null;
        var resizeObserver = null;
        var mutationObserver = null;
        var motionPreference = null;
        var api = { update: update, teardown: teardown };

        function restore(record) {
            record.element.removeAttribute(attribute);
            activeAnimations.delete(record);
            record.state = 'seen';
        }

        function restoreAll() {
            records.forEach(restore);
            if (cleanupTimer !== null) {
                clearTimeout(cleanupTimer);
                cleanupTimer = null;
            }
        }

        function teardown() {
            if (stopped) return;
            stopped = true;
            if (frame !== null) cancelAnimationFrame(frame);
            frame = null;
            restoreAll();
            if (resizeObserver) resizeObserver.disconnect();
            if (mutationObserver) mutationObserver.disconnect();
            window.removeEventListener('resize', layoutChanged);
            window.removeEventListener('error', failOpen);
            window.removeEventListener('unhandledrejection', failOpen);
            document.removeEventListener('load', layoutChanged, true);
            document.removeEventListener('animationend', animationEnded, true);
            if (motionPreference) {
                if (motionPreference.removeEventListener) {
                    motionPreference.removeEventListener('change', preferenceChanged);
                } else if (motionPreference.removeListener) {
                    motionPreference.removeListener(preferenceChanged);
                }
            }
            if (style && style.parentNode) style.parentNode.removeChild(style);
            records = [];
            known.clear();
            activeAnimations.clear();
            if (window.aproposReaderReveal === api) delete window.aproposReaderReveal;
        }

        // A script error can only remove the enhancement. The default document
        // and all unselected text remain fully visible without this script.
        function failOpen() {
            teardown();
        }

        function requestFrame() {
            if (stopped || frame !== null || !viewport) return;
            frame = requestAnimationFrame(render);
        }

        function update(next) {
            if (stopped || !next) return;
            try {
                nativeReduceMotion = next.reduceMotion === true;
                if (nativeReduceMotion) restoreAll();
                if (!Number.isFinite(next.top) || !Number.isFinite(next.bottom) ||
                    next.bottom <= next.top) return;
                viewport = {
                    top: next.top,
                    bottom: next.bottom,
                    reduceMotion: next.reduceMotion === true
                };
                requestFrame();
            } catch (error) { failOpen(); }
        }

        function layoutChanged() {
            needsMeasurement = true;
            requestFrame();
        }

        function preferenceChanged() {
            if (motionPreference && motionPreference.matches) restoreAll();
            requestFrame();
        }

        function scan() {
            var candidates = document.querySelectorAll(proseSelector);
            var nextRecords = [];
            var nextKnown = new Map();
            var count = Math.min(candidates.length, maximumCandidates);
            for (var index = 0; index < count && nextRecords.length < maximumBlocks; index++) {
                var element = candidates[index];
                // Outer lists/quotes animate as one unit, including when the CMS
                // wraps them in divs. Captions and embedded media never animate.
                if (element.closest(excludedSelector) || element.querySelector(mediaSelector) ||
                    !element.textContent.trim()) continue;
                if (element.parentElement && element.parentElement.closest(proseSelector)) continue;
                var record = known.get(element);
                if (!record) {
                    // Leave any author's explicit opt-in attribute untouched.
                    if (element.hasAttribute(attribute)) continue;
                    record = { element: element, top: 0, bottom: 0, state: 'fresh', endsAt: 0 };
                }
                nextRecords.push(record);
                nextKnown.set(element, record);
            }
            records.forEach(function (record) {
                if (!nextKnown.has(record.element)) restore(record);
            });
            records = nextRecords;
            known = nextKnown;
            if (resizeObserver) {
                resizeObserver.disconnect();
                if (document.body) resizeObserver.observe(document.body);
                records.forEach(function (record) { resizeObserver.observe(record.element); });
            }
            needsScan = false;
            needsMeasurement = true;
        }

        function measure() {
            records.forEach(function (record) {
                var top = 0;
                var node = record.element;
                var depth = 0;
                // offsetTop/offsetHeight exclude our cosmetic transform. No
                // per-frame DOM rectangles or transformed height feedback loops.
                while (node && depth < 128) {
                    top += node.offsetTop || 0;
                    node = node.offsetParent;
                    depth++;
                }
                record.top = top;
                record.bottom = top + record.element.offsetHeight;
            });
            needsMeasurement = false;
        }

        function finishAnimations() {
            cleanupTimer = null;
            if (stopped) return;
            try {
                var now = performance.now();
                activeAnimations.forEach(function (record) {
                    if (record.endsAt <= now) restore(record);
                });
                scheduleAnimationCleanup();
            } catch (error) { failOpen(); }
        }

        function scheduleAnimationCleanup() {
            if (cleanupTimer !== null || activeAnimations.size === 0) return;
            var earliest = Infinity;
            activeAnimations.forEach(function (record) { earliest = Math.min(earliest, record.endsAt); });
            cleanupTimer = setTimeout(finishAnimations, Math.max(0, earliest - performance.now()));
        }

        function animationEnded(event) {
            if (event.animationName !== 'apropos-native-reader-arrive') return;
            var record = known.get(event.target);
            if (record && record.state === 'revealing') restore(record);
        }

        function render() {
            frame = null;
            if (stopped || !viewport) return;
            try {
                if (needsScan) scan();
                if (needsMeasurement) measure();
                if (nativeReduceMotion || (motionPreference && motionPreference.matches)) {
                    restoreAll();
                    return;
                }
                var threshold = viewport.bottom - 24;
                records.forEach(function (record) {
                    if (record.state === 'fresh') {
                        if (record.top < viewport.bottom) {
                            restore(record);
                        } else {
                            record.state = 'pending';
                            record.element.setAttribute(attribute, 'pending');
                        }
                    } else if (record.state === 'pending' && record.top <= threshold) {
                        if (record.bottom <= viewport.top) {
                            // A fast jump must never animate content already read.
                            restore(record);
                        } else {
                            record.state = 'revealing';
                            record.endsAt = performance.now() + 620;
                            activeAnimations.add(record);
                            record.element.setAttribute(attribute, 'revealing');
                        }
                    }
                });
                scheduleAnimationCleanup();
            } catch (error) { failOpen(); }
        }

        try {
            // No rule targets ordinary prose until a valid native viewport has
            // explicitly prepared it. Offscreen prose stays readable at 55%.
            style = document.createElement('style');
            style.textContent =
                '[' + attribute + '="pending"]{opacity:.55;transform:translateY(8px);}' +
                '[' + attribute + '="revealing"]{animation:apropos-native-reader-arrive 450ms cubic-bezier(.22,1,.36,1) both;}' +
                '@keyframes apropos-native-reader-arrive{from{opacity:.55;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}' +
                '@media(prefers-reduced-motion:reduce){[' + attribute + ']{opacity:1!important;transform:none!important;animation:none!important;}}';
            (document.head || document.documentElement).appendChild(style);
            if (window.ResizeObserver) resizeObserver = new ResizeObserver(layoutChanged);
            if (window.MutationObserver && document.body) {
                mutationObserver = new MutationObserver(function () {
                    needsScan = true;
                    needsMeasurement = true;
                    requestFrame();
                });
                mutationObserver.observe(document.body, { childList: true, characterData: true, subtree: true });
            }
            if (window.matchMedia) {
                motionPreference = window.matchMedia('(prefers-reduced-motion: reduce)');
                if (motionPreference.addEventListener) {
                    motionPreference.addEventListener('change', preferenceChanged);
                } else if (motionPreference.addListener) {
                    motionPreference.addListener(preferenceChanged);
                }
            }
            window.addEventListener('resize', layoutChanged);
            window.addEventListener('error', failOpen);
            window.addEventListener('unhandledrejection', failOpen);
            document.addEventListener('load', layoutChanged, true);
            document.addEventListener('animationend', animationEnded, true);
            if (document.fonts && document.fonts.ready) {
                document.fonts.ready.then(function () { if (!stopped) layoutChanged(); });
            }
            window.aproposReaderReveal = api;
        } catch (error) { failOpen(); }
    })();
    """#
}
