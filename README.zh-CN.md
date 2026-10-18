# Switch Profile

[English](README.md) · [Tiếng Việt](README.vi.md) · [简体中文](README.zh-CN.md)

一个小巧的 macOS 工具，将其他应用打开的链接分配到正确的 Google Chrome 配置文件（Profile）。

**当前状态：本地演示版（v0.2.0）。** 应用从源码构建为本地 ad-hoc 签名的 `.app`（也可从 GitHub Releases 下载）。首个支持目标是 Google Chrome。

## 工作原理

`在其他应用中点击链接 → macOS → Switch Profile → 匹配规则 → Chrome 配置文件`

用户只需将 Switch Profile 设置为默认浏览器。它接收交给系统默认浏览器的 HTTP/HTTPS 链接，选择配置文件，并将原始 URL 转交给 Chrome。使用内置浏览器或明确指定其他浏览器的应用可能绕过此流程。

应用驻留在菜单栏中，在本地处理路由规则，无需后端服务或 GitHub/GitLab API。仓库访问权限沿用所选 Chrome 配置文件中已有的登录会话。

## 演示规则

以下是默认规则（R1–R4）。你可以在 Settings 中添加、编辑、删除和调整规则顺序（见下文“管理规则”）。规则从上到下依次检查：先是仓库级规则，再是通用域名规则。

| 匹配条件 | Chrome 配置文件 | 验收链接 |
| --- | --- | --- |
| 主机名精确匹配 `git.fis.vn`，任意路径 | `khuepm18` | [GitLab 合并请求](https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests) |
| 主机名为 `github.com`，仓库路径 `/TruckerPoints/trucker-points` 及其子页面 | `khue@truckerpoints.ai` | [trucker-points](https://github.com/TruckerPoints/trucker-points) |
| 主机名精确匹配 `github.com` 的其他链接 | `pmkhue.2013` | [LumiBase](https://github.com/khuepm/LumiBase) |
| 其他主机名 | 备用：最近使用的 Chrome 配置文件（默认）或选定的配置文件 | 任意其他网站 |

仓库规则涵盖 `/issues`、`/pull/123` 等页面，但不得匹配 `/TruckerPoints/trucker-points-other`。必须解析并匹配实际主机名，而非在整个 URL 中搜索字符串。保留原始路径、查询参数和 `#` 后的片段。

主机名按精确匹配处理。`www.github.com`、`api.github.com`、`gist.github.com` 或 `sub.git.fis.vn` 等子域名不匹配 GitHub 或 GitLab 规则，而是交给备用配置文件。

## 界面

- 默认浏览器状态及设置说明。
- 有序的规则列表：添加、编辑、删除和调整规则顺序。
- 已检测到的 Chrome 配置文件，以及各规则的配置文件选择器。
- 备用选择器：最近使用的 Chrome 配置文件或固定的配置文件。
- 配置文件不存在时的明确恢复选项。

配置文件的显示名称和邮箱地址不一定等于目录名称。应用映射到实际存在的目录，如 `Default` 或 `Profile 2`，不会猜测、修改登录数据或静默创建新配置文件。

## v0.2.0 包含的内容

1. 基于 AppKit 的原生 macOS 菜单栏应用，接收 HTTP/HTTPS URL 打开事件。
2. 顺序明确的仓库和域名规则（可在 Settings 中编辑）、备用路由及循环防护。
3. 菜单栏入口、设置和配置文件映射。路由可在终端中用 `--dry-run` 检查。
4. 由一个脚本构建的本地 `.app`，安装与卸载说明见下文。
5. 覆盖路由、配置和启动的自动化测试。手动检查（Chrome 正在运行及已关闭时逐个验证三个配置文件，以及端到端矩阵）记录在[验收矩阵](docs/ACCEPTANCE.md)中。

目标是在正确配置文件的窗口中打开新标签页，必要时创建窗口。窗口复用行为需在实际安装的 Chrome 版本上验证。应用签名、公证和自动更新属于后续范围。

<!-- sp:requirements -->
## 系统要求

- macOS 13 或更高版本（部署目标）。目前仅在 macOS 27 上测试过。
- 安装在 `/Applications` 中的 Google Chrome（稳定版），且至少启动过一次，以便已有配置文件。
- Xcode 命令行工具（`xcode-select --install`），无需安装 Xcode 本身。

<!-- sp:build-install -->
## 构建与安装

在本仓库目录中运行：

```sh
scripts/build-app.sh            # 构建并 ad-hoc 签名 build/SwitchProfile.app
scripts/build-app.sh --install  # 同时复制到 ~/Applications/SwitchProfile.app、注册并打开
```

应用以菜单栏图标形式出现，不显示 Dock 图标。

<!-- sp:configuration -->
## 配置文件映射

从菜单栏图标打开 **Settings…**。**Routing rules** 按检查顺序列出规则，最后是备用（R4）。每条规则都有一个列出 Chrome 中已找到配置文件的选择器。默认规则为 R1 git.fis.vn、R2 github.com/TruckerPoints/trucker-points 和 R3 github.com。

- 首次运行时，Switch Profile 会根据规则表中的身份为 R1–R3 自动识别配置文件，这些行显示 "Auto-detected: matched by …"。点击 **Confirm** 确认，或选择其他配置文件。
- **Detect** 按规则的身份重新查找。如果匹配到多个配置文件，应用不会自动选择，而是由你选择。
- R4 是所有其他主机名的备用。默认是 "Last active Chrome profile"：未匹配的链接在你最近使用的 Chrome 窗口的配置文件中打开；Chrome 未运行时，在 Chrome 上次使用的配置文件中打开，与不使用 Switch Profile 时相同。选择一个配置文件即可固定备用。没有设置备用的现有配置会自动切换到此模式。固定备用的配置文件消失时，链接会在待处理链接窗口中等待。
- 如需查看某个 URL 对应的规则和配置文件而不打开 Chrome，请使用试运行（见“故障排除”中的**在终端中检查路由**）。
- 文本框支持标准编辑快捷键：Cmd+X、Cmd+C、Cmd+V、Cmd+A、Cmd+Z 和 Shift-Cmd-Z。
- 配置文件缺失或账号变更时，会在对应行和菜单中标记（"Profile mapping needs attention …"）。

### 管理规则

- **Add rule**（位于备用上方）打开编辑器：选择 **Match**（Exact host，或 Host and path prefix），输入 **Host**，前缀规则还需输入 **Path prefix**，可选择 **Profile**，然后点击 **Save**。新规则添加在备用正上方，并获得下一个未使用的编号（R5、R6……；编号不会被重复使用）。
- **Edit** 修改规则的匹配条件；配置文件通过该行的选择器修改。**Delete…** 会先请求确认。**Move up** / **Move down** 调整顺序。
- 规则从上到下检查，使用第一条匹配的规则。备用始终在最后，不能编辑、移动或删除。
- Exact host：主机名必须相同（不区分大小写，忽略末尾的点、端口和用户信息）。不支持子域名和通配符（`*.github.com`）：请将每个主机名单独添加为一条规则。
- Host and path prefix：路径必须按完整路径段以该前缀开头，不区分大小写。`/acme/app` 匹配 `/acme/app`、`/acme/app/pull/1` 和 `/acme/app.git`，但不匹配 `/acme/app-other`。查询参数和片段不参与匹配。原始路径、查询参数和片段始终原样转发。
- 无效输入会以红色显示在对应输入框下方：主机名为空或无效（不能包含 `http://`、路径、端口或空格）、路径不以 `/` 开头，或与其他规则重复。
- 如果某条规则因上方更宽泛的规则总是先匹配而永远不会生效（例如 `github.com/acme` 位于 `github.com` 下方），会显示橙色警告。请将更具体的规则上移。
- 添加、编辑、删除或移动规则后，待处理链接窗口中的链接会重新路由。

配置保存在 `~/Library/Application Support/SwitchProfile/config.json`（架构版本 2）。旧版本的文件会照常读取，并在下次更改时以新格式保存，路由结果不变。若文件无效或来自更新的版本，则绝不会被覆盖：菜单显示 "Configuration error – Reset to defaults…"，重置时会保留名为 `config.corrupt-<日期>.json` 的备份。

<!-- sp:default-browser -->
## 设为默认浏览器

在 Settings 中点击 **Set as default browser…**（菜单中也有 "Set as Default Browser…"），并确认 macOS 的提示。之后 Settings 会显示 Switch Profile 正在处理 `http` 和 `https`。

也可以在“系统设置”→“桌面与程序坞”→“默认网页浏览器”中选择。

<!-- sp:troubleshooting -->
## 故障排除

- **"Chrome profiles unavailable" / Local State 错误。** Switch Profile 读取 `~/Library/Application Support/Google/Chrome/Local State`。请确认 Chrome 已安装并至少启动过一次。在 macOS 27 上，系统可能拒绝应用读取该文件；请在“系统设置”→“隐私与安全性”中为 Switch Profile 授予访问权限（App Data 或“完全磁盘访问权限”），然后在 Settings 中点击 **Refresh**，或在待处理链接窗口中点击 **Refresh profiles**。Settings 和试运行会显示 "Chrome profiles unavailable" 及上述解决方法，而不是 "no profile set"。试运行使用终端的权限，因此运行 `--dry-run` 的终端应用也需要同样的 App Data 或“完全磁盘访问权限”。
- **待处理链接窗口。** 暂时无法打开的链接（未设置配置文件、配置文件缺失、无法打开 Chrome）会被保留，不会丢弃。从菜单中的 "Pending links (n)…" 打开窗口，使用 **Open once**、**Open and use for R…**、**Retry** 或 **Discard**。
- **另一个副本是默认浏览器。** 如果 Settings 显示 "Another copy at … is the default; remove it."，请删除该副本，用 `lsregister -u <路径>`（完整路径见“卸载”）取消注册，然后重新设为默认。
- **Gatekeeper。** 应用为 ad-hoc 签名且未经公证。如果 macOS 阻止打开，请按住 Control 键点击应用并选择“打开”，或在“系统设置”→“隐私与安全性”中允许。
- **在终端中检查路由。** 试运行（dry run）会打印规则、配置文件目录和传给 Chrome 的确切参数，不会打开或写入任何内容：

  ```sh
  build/SwitchProfile.app/Contents/MacOS/SwitchProfile --dry-run [--assume-chrome running|closed] URL...
  ```

  试运行使用 `config.json` 中你的规则，并在 `rules:` 行中按顺序列出。在最近使用模式下，备用显示 `R4: last active Chrome profile`，argv 中没有 `--profile-directory`。

<!-- sp:restore -->
## 恢复之前的默认浏览器

将 Switch Profile 设为默认时，应用会记录之前的浏览器。在 Settings 中点击 **Restore previous default (…)…**。也可以在“系统设置”→“桌面与程序坞”→“默认网页浏览器”中重新选择。

<!-- sp:remove -->
## 卸载

1. 恢复之前的默认浏览器（见上文）。
2. 从菜单退出 Switch Profile（"Quit Switch Profile"）。
3. 删除 `~/Applications/SwitchProfile.app`（如构建过，也删除 `build/SwitchProfile.app`）。
4. 从 Launch Services 取消注册：

   ```sh
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u ~/Applications/SwitchProfile.app
   ```

5. 删除设置目录 `~/Library/Application Support/SwitchProfile/`。

<!-- sp:version -->
## 版本

0.2.0（build 2）。最低 macOS 13（部署目标）；目前仅在 macOS 27 上测试过。

<!-- sp:signing -->
## 签名限制

应用由 `scripts/build-app.sh` 进行 ad-hoc 签名，未经公证，仅供在构建它的电脑上本地使用。Developer ID 签名、公证和自动更新属于后续范围。

<!-- sp:known-limitations -->
## 已知限制

- 使用内置浏览器的应用，或直接打开特定浏览器的应用，会绕过 Switch Profile。
- 链接在新标签页还是新窗口中打开由 Chrome 决定。
- 目前仅支持 Google Chrome。
- 规则仅精确匹配主机名，不支持通配符或子域名规则。

## 验收标准

- 从其他应用点击三个示例链接，均进入指定的配置文件。
- 即使前台是另一个 Chrome 配置文件的窗口，路由仍正确。
- Chrome 或 Switch Profile 尚未运行时也能正常打开链接。
- 其他域名在最近使用的 Chrome 配置文件或选定的备用配置文件中打开，不会再次打开 Switch Profile。
- 配置文件缺失或无法唯一识别时，要求明确选择处理方式，不静默切换账号。
- 连续打开多个链接时，不丢失、不重复。
- 保留查询参数和片段；相似域名及仓库路径前缀不会误匹配。
- 用户可以恢复之前的默认浏览器。

各项标准的测试状态见[验收矩阵](docs/ACCEPTANCE.md)。

## 开发与待办事项

请查看[开发待办事项](docs/BACKLOG.md)，了解 Epic、实施 Issue、优先级、依赖关系和完成标准。使用 `swift build` 构建，使用 `swift test` 运行测试。

工作流程：创建或复用 Issue → 在 GitHub Project 中标记为 **In Progress**（未使用 Project 时使用 `status:in-progress` 标签）→ 创建以 Issue 编号开头的分支 → 提交关联 Issue 的 PR → 通过适用检查 → 合并到 `main` → 将已解决的 Issue 标记为 **Done** 并关闭。完全解决 Issue 的 PR 使用 `Closes #<id>`。实施 Issue 在满足验收标准前保持开放。

## 技术参考

- [Apple：通过 AppKit 接收 URL 打开事件](https://developer.apple.com/documentation/AppKit/NSApplicationDelegate/application(_:open:))
- [Chromium：用户数据与配置文件目录](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md)
