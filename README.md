# OhMyBoop

原生 macOS 开发工具箱，SwiftUI + AppKit，支持 macOS 14 及以上。左侧按 JSON、YAML、CSV、XML / HTML、CSS、SQL、JavaScript、Markdown 和文本组织；右侧工具条对同一份草稿连续操作。其他数据类型包含 URL、Base64、JWT、哈希、数字、日期、本地化等。保留 Boop 1.4.0 随附的全部 72 个脚本。

## 使用

```sh
zsh scripts/build-app.sh
open dist/OhMyBoop.app
```

也可用 Xcode 打开 `OhMyBoop.xcodeproj`。Swift Package 支持 `swift run` 和测试；应用分发使用 Xcode 构建以正确包含依赖资源。添加源文件或修改 `project.yml` 后运行 `xcodegen generate`。

- 左侧选择格式，输入文本，直接点击格式化、压缩等动作。窄窗口的低频动作收进“更多”；转换操作从工具条或“转换为”菜单进入。
- 同一格式共用草稿、选区、滚动位置和撤销历史。切换动作不会切换文本。`⌘ Z` / `⇧⌘ Z` 撤销/重做；`⌘ Return` 执行此格式最近一次动作，名称显示在底部和系统“处理”菜单。
- 原位处理可撤销。转换和哈希显示独立只读结果，可复制或关闭，不覆盖原文或目标格式草稿；修改输入会清除旧结果。统计动作只显示反馈。
- 支持选区的动作只处理选区。ASCII/Hex、本地化转换、合并行和测试脚本明确按全文处理。动作提示及编辑栏显示作用范围。
- 搜索匹配格式、动作中文名、英文元数据和标签；选择结果只定位，不自动执行。动作收藏在“更多”菜单管理，并可从“已收藏动作”运行。
- JSON、YAML、JavaScript 默认启用对应的 Tree-sitter 着色，其他格式默认纯文本。可手动调整高亮偏好。转换结果按输出格式高亮。
- 输入停止 180 ms 后后台着色；只查询可见区域及上下缓冲，滚动和尺寸变化触发补色。明确语言超过 100,000 UTF-16 单元、无提示自动模式超过 8,000 单元时回退纯文本。
- “去反斜杠”沿用通用脚本，不等同解析 JSON 字符串；“排序（含数组）”会重排数组元素。

## 草稿与升级

草稿位于 `~/Library/Application Support/OhMyBoop/workspace.json`，编辑停止 400 ms 后自动保存，应用失焦和正常退出也会保存。文件原子写入、权限 `0600`，是本地明文。结果预览和撤销历史只在本次运行中保留。

首次读取 v1 工具草稿时，先在原文件旁生成 `.v1-backup` 字节副本，再保存 v2 格式工作区。当前选中工具的草稿优先成为所属格式的活动草稿，否则使用非空主动作草稿或固定顺序的非空草稿。每个原工具草稿都保留来源 ID，能够通过“历史草稿”恢复；恢复前也会归档当前内容。收藏保留。

迁移备份失败时，仍恢复旧内容供查看，但禁止本次覆盖文件；损坏或未知版本文件也不会被空草稿覆盖。原名 OhMyDevOps 的目录仍作为读取后备，新目录有文件时优先使用新文件，旧文件不覆盖。

## 本地执行与验证

每次动作启动独立 JavaScriptCore 子进程，只提供随应用分发的脚本模块，不发送网络请求。8 秒超时和脚本错误保留原文；执行期间可切到其他格式，结果只回写原工作区。同一工作区拒绝并发动作。

```sh
swift test --disable-swift-testing
zsh scripts/build-app.sh
codesign --verify --deep --strict dist/OhMyBoop.app
dist/OhMyBoop.app/Contents/MacOS/OhMyBoop --validate-highlighter /tmp/highlighter-resources.json
```

测试覆盖全部 72 个脚本、真实子进程和死循环超时、v1 迁移备份/失败保护、多份归档恢复、UTF-16 选区转换、连续撤销、结果视图替换及高亮。`/tmp/ohmyboop-*.png` 为 AppKit 离屏渲染，不能替代真实窗口连续输入/输入法/滚动验收。

`dist/OhMyBoop.app` 是临时签名应用，对外分发仍需开发者签名和公证。

## 代码结构

- `Catalog.swift`：脚本元数据读取。
- `FormatCatalog.swift`：格式、动作、处理范围、结果类型和搜索映射。
- `DraftStorage.swift`：v1/v2 存储、迁移、归档与备份。
- `Workspace.swift`：格式会话、撤销、结果预览与保存协调。
- `ContentView.swift`：格式侧栏、动作工具条、结果与历史草稿界面。
- `ScriptEngine.swift`：脚本协议、CommonJS 模块和进程执行。
- `Highlighting.swift`：独立解析树与可见区域着色。
- `OhMyBoopApp.swift`：应用、脚本进程入口和动作快捷键。

方案见 [工作区重构方案](docs/format-workspace-proposal.md)，高亮选型历史见 [Tree-sitter 验证](docs/tree-sitter-validation.md)。

## 致谢

特别感谢 [Ivan Mathy](https://github.com/IvanMathy) 创建并开源 [Boop](https://github.com/IvanMathy/Boop)，以及所有 Boop 贡献者。OhMyBoop 的功能灵感及内置的 72 个工具脚本来自 Boop；本项目在此基础上提供按格式组织的工作区和连续操作的编辑状态。

脚本来自 [Boop](https://github.com/IvanMathy/Boop)，其 [MIT 许可](https://github.com/IvanMathy/Boop/blob/main/LICENSE)及原始作者信息保留在 `Resources/ThirdPartyNotices.txt` 和脚本文件中。依赖库沿用其各自的许可声明。

高亮使用 [SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter)、[Tree-sitter](https://github.com/tree-sitter/tree-sitter) 及 JSON / YAML / JavaScript 语法。来源与固定版本见 [语法说明](Vendor/BoopGrammars/README.md)，许可包含在应用的 ThirdPartyNotices.txt。
