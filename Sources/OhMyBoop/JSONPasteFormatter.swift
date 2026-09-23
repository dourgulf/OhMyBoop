// Created by lidawen.
import JavaScriptCore

enum JSONPasteFormatter {
    static func format(_ source: String) -> String? {
        // Match Format JSON's parsing, ordering and two-space indentation.
        // Parse valid JSON first so meaningful escapes in values remain intact.
        guard let context = JSContext(), let formatter = context.evaluateScript(#"""
        (function(source) {
            function pretty(text) { return JSON.stringify(JSON.parse(text), null, 2); }
            try {
                var value = JSON.parse(source);
                if (typeof value === 'string') {
                    try { return pretty(value); } catch (_) { return value; }
                }
                return JSON.stringify(value, null, 2);
            } catch (_) {}
            try {
                var decoded = JSON.parse('"' + source + '"');
                try { return pretty(decoded); } catch (_) {
                    return decoded === source ? null : decoded;
                }
            } catch (_) {}
            var stripped = source.replace(/\\(.?)/g, function(_, next) {
                return next === '0' ? '\u0000' : next;
            });
            try { return pretty(stripped); } catch (_) {
                return stripped === source ? null : stripped;
            }
        })
        """#), let result = formatter.call(withArguments: [source]),
              !result.isNull, !result.isUndefined else { return nil }
        return result.toString()
    }
}
