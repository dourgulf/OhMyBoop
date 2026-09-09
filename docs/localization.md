# Localization

The app supports English and Simplified Chinese. Settings offers Follow system, 简体中文, and English. Changes are saved immediately and take effect after restarting, keeping native macOS menus, custom UI, and script workers aligned. Follow system chooses the first supported language in the preferred-language list (Chinese variants use Simplified Chinese), falling back to English.

`Resources/en.lproj/Localizable.strings` and `Resources/zh-Hans.lproj/Localizable.strings` contain UI, action/group names, status text, and known script diagnostics. Chinese source strings are stable lookup keys. `L10n` resolves the launch language and the correct bundle for both Xcode and SwiftPM; SwiftPM lowercases language directory names. Format/action IDs, grouping keys, archives, and user text are never translated. Existing archive labels are localized only for display.

The application deliberately resolves display strings against the launch language, rather than mixing SwiftUI's locale with independently running AppKit and JavaScriptCore code. Switching language does not recreate editors or modify drafts; restart is required. `app.language` stores the choice, and an app-scoped `AppleLanguages` preference aligns standard macOS menus after restart. Choosing Follow system removes that override. Font reset does not change the language.

Each worker request carries the caller's language. JSON diagnostics return a message key, placeholder arguments, and a UTF-16 offset; the Swift bridge translates the message without changing offsets or source text. Known script status messages are translated, including counts. Arbitrary runtime exceptions from JavaScriptCore, external parser libraries, or the OS are preserved verbatim instead of guessed translations. Technical format/font names remain unchanged.

When adding text, add matching keys to both tables, preserve `%@` placeholder counts/order, and use full-message templates rather than concatenating translated sentence fragments. Do not translate script outputs or persisted IDs. Counts use labels such as “Words: 1” to avoid incorrect English singular/plural forms.

Validation:

```sh
OHMYBOOP_LANGUAGE=en swift test --disable-swift-testing
OHMYBOOP_LANGUAGE=zh-Hans swift test --disable-swift-testing --skip-build
zsh scripts/build-app.sh
python3 scripts/validate-localization.py
```

`OHMYBOOP_LANGUAGE` is a process-only override for automation; it does not write user preferences. CI runs both language suites. Tests cover resource parity, action coverage, placeholders, system fallback, preference persistence, Unicode error locations, worker language propagation, and native UI captures.

During validation, sampling reproduced an existing `Process.waitUntilExit()` stall after `isRunning` was already false. The redundant synchronous wait was removed; the existing timeout/termination path remains unchanged.
