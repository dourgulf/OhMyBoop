# OhMyBoop 编辑器着色方案调研

调研日期：2026-09-08。范围：原生 macOS SwiftUI + AppKit `NSTextView` 工具箱；本次只比较方案，不接入依赖、不修改编辑器。以下推荐属于设计判断，未经本项目性能实测。

## 建议

目前优先验证 **HighlighterSwift / highlight.js + 保守语言识别 + 通用文本兜底**；如果实际大文本编辑延迟或结构识别质量不达标，再对比 **Tree-sitter + SwiftTreeSitter，按需要采用 Neon**。更现代的体验主要来自正确判断内容、稳定着色和保持输入状态，不能只按支持语言数量选库。

Boop 的通用规则可以继续作为未知文本的参考。指定参考提交中的 `BoopLexer` 将常见关键字、字符串、数字、注释和日期、MD5 等模式放在同一个词法器中，并未按语言选择独立语法。这适合随手粘贴，但准确区分不同语言中的同形文本能力有限。[BoopLexer 固定版本](https://github.com/IvanMathy/Boop/blob/5cf6914381f6ed6ef004c3a7d470f241a248fcb6/Boop/Boop/Editor/BoopLexer.swift)

## 路线比较

| 路线 | 适合的目标 | 对 OhMyBoop 的取舍 |
| --- | --- | --- |
| 通用词法规则 | 未知片段、日志、临时文本 | 保留作兜底，减少不确定的关键字着色；长期靠增加规则难以覆盖语言上下文 |
| highlight.js + HighlighterSwift | 较快接入广泛语言和原生属性文本 | 当前首选验证候选；需补识别策略、后台调度与结果版本检查 |
| Tree-sitter + SwiftTreeSitter / Neon | 持续编辑、大文档、结构与嵌套语言 | 原生编辑器长期路线；语法包、查询和失效范围管理成本更高 |
| TextMate + Shiki | 重视 VS Code 语法与主题生态 | 值得保留，但当前 JSC 桥接工作更多，不是现成 NSTextView 方案 |
| LSP semantic tokens | 工程上下文中的类型、符号、声明关系 | 目前收益不足；未来扩展为代码工作区时再考虑 |

表内成本和适用性为针对本项目的判断，能力证据见下文。

## highlight.js：现实的轻量入口

官方 API 有明确语言的 `highlight`，也有 `highlightAuto(code, languageSubset)`。后者提供检测语言、`relevance` 与可能存在的 `secondBest`。这些是启发式结果，不能把 relevance 当成正确率百分比；候选集可以按工具收窄。[highlight.js API](https://highlightjs.readthedocs.io/en/latest/api.html)

旧 **Highlightr 已明确表示从 2026 年起不再积极维护，并推荐 HighlighterSwift**，不宜作为新的默认依赖。[Highlightr 官方说明](https://github.com/raspu/Highlightr)

HighlighterSwift 当前 README 标注 3.1.0，包装 highlight.js 11.11.1，返回 `NSAttributedString`，支持自动检测。其主题 CSS 做过适配，不能直接拷贝任意上游主题；编辑器不应使用其把行号加入结果字符串的功能。[HighlighterSwift README](https://github.com/smittytone/HighlighterSwift)

源码确认它通过 `JSContext` 执行打包资源。现有 `highlight` 自动模式只传文本，最终只返回属性字符串：**没有直接暴露候选集参数、检测语言或评分**。因此完整识别体验仍需薄适配层或补充 API；同时要验证 HTML 转换后的原文一致性和异常路径，不能把返回属性字符串直接等同于编辑器无损接入。[Highlighter.swift](https://github.com/smittytone/HighlighterSwift/blob/main/Sources/Highlighter/Highlighter.swift)

其包声明 Swift tools 5.9、macOS 11；本项目当前声明 Swift tools 6.0、macOS 14、Swift 5 语言模式，从声明看最低版本不冲突，但未在本项目构建该依赖，也未验证并发使用。采用时应固定版本并验证随包 JS、主题资源完整性。[上游 Package.swift](https://github.com/smittytone/HighlighterSwift/blob/main/Package.swift)

## Tree-sitter：更适合持续编辑的结构路线

Tree-sitter 建立并增量更新语法树，设计目标包括逐键解析和在语法不完整时仍提供有用结果；这些是上游能力与目标，不代表本项目已达到输入延迟指标。[Tree-sitter 简介](https://tree-sitter.github.io/tree-sitter/)

着色通过查询给节点分配类别；嵌套语言还需要 injection 配置。必须为支持语言维护对应 parser 和 queries，并明确片段边界。它不会凭空识别任意无文件名剪贴板文本的语言。[Tree-sitter 着色文档](https://tree-sitter.github.io/tree-sitter/3-syntax-highlighting.html)

SwiftTreeSitter 是 Swift 接口，上游将更高层的编辑器集成指向 Neon。[SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter)

Neon 提供 NSTextView 集成、UTF-16 范围接口、后台处理和 fallback / primary / secondary 分层着色。但 README 明确提醒 **main 尚未准备好发布**；当前文档主要面向 main，不能假定已发布版本拥有完全相同 API。正式选用前须固定具体版本或提交，核对文档与代码，验证 TextKit 路径。[Neon README](https://github.com/ChimeHQ/Neon)、[发布版本](https://github.com/ChimeHQ/Neon/releases)

建议先用 JSON、JavaScript 等少量实际高频语法做比较；只有增量解析带来的收益超过语言包和生命周期维护成本时，再扩展。

## TextMate / Shiki：生态宽，但原生集成要算账

TextMate 使用带上下文的正则语法和 scope，支持嵌套/注入；主题负责 scope 到样式的映射。它不是 Boop 那种全局通用关键词表。[VS Code 官方语法说明](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide)

Shiki 复用 TextMate 语法与主题，提供显式语言加载和 token 化能力。它是可嵌入的 JavaScript 高亮器，并非现成的原生编辑视图。[Shiki 简介](https://shiki.style/guide/)

不能因为已有 JavaScriptCore 就断言 Shiki 可直接运行：默认引擎使用 Oniguruma WASM；纯 JS 引擎把 Oniguruma 正则转换为 JavaScript RegExp，其运行目标影响语法兼容性。当前文档还对预编译语言包给出尚不支持的警告。应先在最低 macOS 的真实 `JSContext` 中验证打包/加载、正则特性、语言样本与失败回退。[Shiki 引擎说明](https://shiki.style/guide/regex-engines)

Shiki 的 GrammarState 能保存语法上下文，但不是现成的 NSTextView 编辑失效、选区、撤销管理器；要为任意位置修改自行维护相应缓存与传播。[Grammar State](https://shiki.style/guide/grammar-state)

## LSP：留到有工程语义需求时

语义 token 可以借助项目上下文识别符号角色，通常叠加在语法着色之上；语言服务器加载和分析会产生延迟。[VS Code 官方语法说明](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide)

对当前无工程、无依赖上下文的临时转换工具，我判断维护语言服务器生命周期和文档同步不划算。只有未来需要代码跳转、补全、跨文件符号一致性时再评估；“更现代”本身不是采用门槛。

## 语言识别比换引擎更重要

以下是建议的产品策略，不是各库自带的保证：

1. 每个工具编辑状态保存 `自动 / 指定语言 / 通用文本 / 纯文本` 选择。用户指定优先于自动判断，纯文本应始终可选。
2. 自动模式先结合工具输入/输出契约与内容。JSON 格式化提供强提示；大小写转换不提供语言提示；不能把 72 个工具硬编码成 72 种语言。
3. 转换后根据输出重新判断：整篇 JSON → YAML 成功后可更新语言；仅转换选区不能假定整篇都变成 YAML；Base64 / JWT 解码后应检查实际输出；散列结果回到通用或纯文本。只改变有效语言，不覆盖用户的手动选择。
4. 粘贴、转换完成与短暂停顿时检测，避免每次输入都在语言间跳变；歧义和短文本宁可保守回退。
5. 日志采用字段识别：时间、级别、URL、路径、标识符等；明确边界内的 JSON 可嵌套解析。不要把整个混合日志强判为 JSON，也不要让通用正则覆盖字符串内部的专用语法结果。

例如 `ERROR 2026-09-08 payload={"ok":false}` 的价值是看清级别、时间和 payload 结构，而不是强行选择一种编程语言。CSV、HTTP、diff 同样可以拥有面向内容的专用模式。宽泛适应性来自允许多种内容类型和可靠兜底。

## 主题与状态边界

建议将 `文本 → 语言/内容模式 → token 类别与范围 → 主题样式 → TextKit` 分开。主题切换只重映射样式；语言引擎更新不需要重写深浅色方案。TextMate scope 和 Tree-sitter capture 可归一到产品自己的小型类别集，再为日志增加时间、级别等类别。这是设计建议，借鉴了上游 tokenization 与 theming 分离的做法。[VS Code 官方说明](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide)

每个功能保留自己的文本、手动语言选择和文档版本；解析缓存可按需回收。后台结果携带工具 ID 与文本版本，过期结果丢弃。着色只应用显示属性，不替换全文，不加入用户撤销记录，不污染草稿。中文输入法组合阶段、选区、滚动位置和工具间切换都是必须验证的边界。

## 实施前的验证门槛

- 先准备真实样本：合法与未闭合 JSON、XML/HTML、SQL、YAML、Shell、中文与 emoji、日志夹 JSON、超长单行和纯文本；同时覆盖转换前后语言变化。
- 比较 HighlighterSwift 与少量 Tree-sitter 语法，记录冷启动、首次着色、逐键主线程耗时、滚动响应、内存和包体增量。10 KB / 100 KB / 1 MB 可作为样本梯度，不当作预设支持上限。
- 确认输入法、撤销重做、切换功能、草稿恢复、快速连续转换、深浅色切换不受影响；原文字节内容和可见文本保持一致。
- 为耗时、错误、未知语言设置通用或纯文本回退；精确时间预算和大文本阈值依据目标 Mac 测量后确定。
- 若轻量方案满足样本质量与响应要求，就停留在该路线；只有明确的大文档、嵌套语法或持续编辑问题才推动 Tree-sitter 升级。

本次完成官方文档和部分源码核对；未安装这些库，未进行应用内构建、真实性能比较或 UI 验收。
