# Switch Profile

[English](README.md) · [Tiếng Việt](README.vi.md) · [简体中文](README.zh-CN.md)

一个小巧的 macOS 工具，将其他应用打开的链接分配到正确的 Google Chrome 配置文件（Profile）。

**当前状态：规划与仓库初始化。** 仓库目前包含项目文档和开发待办事项，尚无可运行的应用或可下载的发布版本。首个支持目标是 Google Chrome。

## 工作原理

`在其他应用中点击链接 → macOS → Switch Profile → 匹配规则 → Chrome 配置文件`

用户只需将 Switch Profile 设置为默认浏览器。它接收交给系统默认浏览器的 HTTP/HTTPS 链接，选择配置文件，并将原始 URL 转交给 Chrome。使用内置浏览器或明确指定其他浏览器的应用可能绕过此流程。

应用计划驻留在菜单栏中，在本地处理路由规则，无需后端服务或 GitHub/GitLab API。仓库访问权限沿用所选 Chrome 配置文件中已有的登录会话。

## 演示规则

仓库级规则优先于通用域名规则。

| 匹配条件 | Chrome 配置文件 | 验收链接 |
| --- | --- | --- |
| 主机名精确匹配 `git.fis.vn`，任意路径 | `khuepm18` | [GitLab 合并请求](https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests) |
| 主机名为 `github.com`，仓库路径 `/TruckerPoints/trucker-points` 及其子页面 | `khue@truckerpoints.ai` | [trucker-points](https://github.com/TruckerPoints/trucker-points) |
| 主机名精确匹配 `github.com` 的其他链接 | `pmkhue.2013` | [LumiBase](https://github.com/khuepm/LumiBase) |
| 其他主机名 | 用户选择的备用配置文件 | 任意其他网站 |

仓库规则涵盖 `/issues`、`/pull/123` 等页面，但不得匹配 `/TruckerPoints/trucker-points-other`。必须解析并匹配实际主机名，而非在整个 URL 中搜索字符串。保留原始路径、查询参数和 `#` 后的片段。

## 计划中的演示界面

- 默认浏览器状态及设置说明。
- 已检测到的 Chrome 配置文件，以及各规则的配置文件选择器。
- 备用配置文件选择器。
- URL 输入框、**检查规则**和**测试打开**按钮。
- 配置文件不存在时的明确恢复选项。

配置文件的显示名称和邮箱地址不一定等于目录名称。应用必须映射到实际存在的目录，如 `Default` 或 `Profile 2`，不得猜测、修改登录数据或静默创建新配置文件。

## 实施计划

1. 验证 Chrome 正在运行及已关闭时，三个配置文件均能正确打开链接。
2. 使用 AppKit 构建原生 macOS 应用，接收 HTTP/HTTPS URL 打开事件。
3. 实现顺序明确的仓库和域名规则、备用路由及循环防护。
4. 添加菜单栏入口、设置、配置文件映射和规则预览。
5. 执行端到端测试，打包本地 `.app` 演示版，并提供安装与卸载说明。

目标是在正确配置文件的窗口中打开新标签页，必要时创建窗口。窗口复用行为需在实际安装的 Chrome 版本上验证。演示版预计需要 2–3 个开发工作日，具体取决于配置文件启动验证结果；应用签名、公证和自动更新属于后续范围。

## 验收标准

- 从其他应用点击三个示例链接，均进入指定的配置文件。
- 即使前台是另一个 Chrome 配置文件的窗口，路由仍正确。
- Chrome 或 Switch Profile 尚未运行时也能正常打开链接。
- 其他域名使用明确选择的备用配置文件，不循环调用 Switch Profile。
- 配置文件缺失或无法唯一识别时，要求明确选择处理方式，不静默切换账号。
- 连续打开多个链接时，不丢失、不重复。
- 保留查询参数和片段；相似域名及仓库路径前缀不会误匹配。
- 用户可以恢复之前的默认浏览器。

## 开发与待办事项

请查看[开发待办事项](docs/BACKLOG.md)，了解 Epic、实施 Issue、优先级、依赖关系和完成标准。可运行版本实现后，将补充构建和安装命令。

工作流程：创建或复用 Issue → 在 GitHub Project 中标记为 **In Progress**（未使用 Project 时使用 `status:in-progress` 标签）→ 创建以 Issue 编号开头的分支 → 提交关联 Issue 的 PR → 通过适用检查 → 合并到 `main` → 将已解决的 Issue 标记为 **Done** 并关闭。完全解决 Issue 的 PR 使用 `Closes #<id>`。实施 Issue 在满足验收标准前保持开放。

## 技术参考

- [Apple：通过 AppKit 接收 URL 打开事件](https://developer.apple.com/documentation/AppKit/NSApplicationDelegate/application(_:open:))
- [Chromium：用户数据与配置文件目录](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md)
