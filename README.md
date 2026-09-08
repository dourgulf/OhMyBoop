# OhMyBoop

当前分支为 **Tree-sitter 验证版**。验证 JSON、YAML、JavaScript 的增量解析；与 HighlighterSwift 的对比见 [验证报告](docs/tree-sitter-validation.md)。

原生 macOS 开发工具箱，SwiftUI + AppKit，支持 macOS 14 及以上。

左边是分类、搜索和收藏列表，右边是当前功能的文本编辑区。接入本机 Boop 1.4.0 随附的全部 72 个功能，包括 JSON / YAML / CSV、格式化和压缩、Base64 / URL / HTML 编解码、哈希、文本处理、日期及数字转换。

## 使用

```sh
zsh scripts/build-app.sh
open dist/TreeSitterValidation/OhMyBoop.app
```

用 Xcode 打开 `OhMyBoop.xcodeproj` 可运行标准 macOS 应用。Swift Package 仍支持 `swift run` 和 `swift test`；应用分发使用 Xcode 构建，以正确包含依赖的资源包。项目文件由 `project.yml` 生成，仅在修改该配置时需要运行 `xcodegen generate`。

- 左侧选择功能，在右侧输入文本，点击「执行」或按 `⌘ Return`。
- 结果直接替换当前文本；选中文本时通常只转换选区。四个沿用 Boop 全文接口的工具会在界面明确标示「此功能处理全文」。
- `⌘ Z` 撤销；每个功能拥有独立的编辑器及撤销历史。
- 复制、粘贴替换、清空按钮只作用于当前功能，替换与清空可撤销。
- 各功能分别保存文本、光标 / 选区、垂直滚动位置；切换功能保留全部编辑状态。重启恢复草稿、选区、滚动位置、收藏及上次选中的功能，撤销历史仅保留到退出应用。
- 搜索支持英文名称、描述、标签和中文分类名称。
- 高亮支持 JSON、YAML、JavaScript，每个功能独立记忆语言与解析树。采用 GitHub 风格的深浅配色。自动模式仅使用工具提示或以 `{` / `[` 开头的 JSON 外形判断；Tree-sitter 本身不提供自动语言检测，其他文本请手动指定语言。
- 输入停止 180 ms 后后台着色，只更新临时显示属性。明确语言超过 100,000 个 UTF-16 单元、无语言提示的自动识别超过 8,000 个单元时使用纯文本回退。

## 草稿与执行

草稿保存在 `~/Library/Application Support/OhMyBoop/workspace.json`，编辑停止 400 ms 后自动保存，应用失焦和正常退出时也会保存。文件采用原子写入，权限为 `0600`。如果旧文件损坏，会保留原文件并在界面提示，不会用空白草稿覆盖它。

从原名 OhMyDevOps 升级时，如果新目录中尚无草稿，会自动读取旧目录的草稿、选区、滚动位置和收藏，随后保存到 OhMyBoop 目录；旧文件保持不变。已有 OhMyBoop 草稿时优先使用新文件。

文本在本机处理，不发送网络请求。草稿为本地明文文件。每次执行启动独立 JavaScriptCore 子进程，只提供随应用分发的脚本模块；超过 8 秒停止该进程并保留原文。脚本错误也不会回写中间结果。执行期间可切换到其他功能，完成后结果写回原来的功能。

## 开发与验证

```sh
swift test --disable-swift-testing
zsh scripts/build-app.sh
codesign --verify --deep --strict dist/TreeSitterValidation/OhMyBoop.app
```

测试覆盖全部 72 个脚本的代表性输入、7 个依赖库、中文与 Emoji、UTF-16 选区、错误时原文保留、真实脚本子进程及死循环超时、独立撤销、草稿存取和损坏文件保护。界面测试额外输出 `/tmp/ohmyboop-preview.png`，属于 AppKit 离屏渲染，不代替真实窗口交互验收。

`dist/TreeSitterValidation/OhMyBoop.app` 为本机构建、临时签名的应用，不需要安装 Boop；对外分发前需配置开发者签名与公证。构建架构跟随当前 Mac。

## 代码结构

- `Catalog.swift`：读取工具元数据与分类。
- `ScriptEngine.swift`：Boop 脚本状态协议、CommonJS 模块与独立进程执行。
- `Workspace.swift`：独立编辑会话、撤销与持久化。
- `ContentView.swift`：分列界面及保留的 NSTextView。
- `OhMyBoopApp.swift`：应用入口及脚本进程入口。
- `Resources/scripts/`：从本机 Boop 复制的脚本和依赖，不修改原脚本。

## 致谢

特别感谢 [Ivan Mathy](https://github.com/IvanMathy) 创建并开源 [Boop](https://github.com/IvanMathy/Boop)，以及所有 Boop 贡献者。OhMyBoop 的功能灵感及内置的 72 个工具脚本来自 Boop；本项目在此基础上提供左右分列界面和各功能独立的编辑状态。

脚本来自 [Boop](https://github.com/IvanMathy/Boop)，其 [MIT 许可](https://github.com/IvanMathy/Boop/blob/main/LICENSE)及原始作者信息保留在 `Resources/ThirdPartyNotices.txt` 和脚本文件中。依赖库沿用其各自的许可声明。

高亮使用 [SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter)、[Tree-sitter](https://github.com/tree-sitter/tree-sitter) 及 JSON / YAML / JavaScript 语法。来源与固定版本见 [语法说明](Vendor/BoopGrammars/README.md)，许可包含在应用的 ThirdPartyNotices.txt。
