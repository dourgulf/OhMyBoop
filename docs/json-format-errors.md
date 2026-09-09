# JSON formatting diagnostics

Formatting still uses JavaScriptCore `JSON.parse` and `JSON.stringify`. On parse failure, `lib/json-diagnostics.js` locates the first syntax error and returns a Chinese explanation with a UTF-16 offset. The script worker maps selected-text offsets back to the full document. Valid input never goes through this diagnostic scanner.

The editor status displays one-based line and column numbers. Columns count Swift characters (including emoji as one character); CRLF counts as one newline. The first offending character has a translucent red background. Newline and end-of-input errors use a red position block, including in an empty document. The editor scrolls to the error without changing the selection or inserting an undo operation.

Diagnostics are produced when the user runs Format JSON, not continuously while typing. Editing, restoring a draft, or starting another action clears the previous diagnostic. Syntax foreground colors and diagnostic background colors are independent. Diagnostics are not persisted in drafts.

The scanner covers objects, arrays, strings and escapes, numbers, literals, separators, and trailing content. It stops at the first error; missing-token locations indicate where the token was expected. A trailing comma is marked on the comma itself. When another item follows without a comma, the marker sits immediately after the previous value, before intervening whitespace or newlines. Unexpected closing delimiters retain their actual position. For very deep malformed input, a depth limit stops further diagnosis. If a native parse failure cannot be classified, the native error message is retained without inventing a position. Worker timeout and process errors keep their existing messages and do not fabricate a source marker.

`JSONDiagnosticsTests` checks worker round-trips, selected-document coordinates, emoji/CRLF, input/selection/undo preservation, diagnostic clearing, and native screenshots for character, newline, EOF, and empty-input errors in both themes.
