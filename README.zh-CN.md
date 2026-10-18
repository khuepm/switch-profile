# Switch Profile

[English](README.md) · [Tiếng Việt](README.vi.md) · [简体中文](README.zh-CN.md)

一个小巧的 macOS 工具，将其他应用打开的链接分配到正确的 Google Chrome 配置文件（Profile）。

**当前状态：本地演示版（v0.2.0）。** 应用从源码构建为本地 ad-hoc 签名的 `.app`（也可从 GitHub Releases 下载）。首个支持目标是 Google Chrome。

## 工作原理

`在其他应用中点击链接 → macOS → Switch Profile → 匹配规则 → Chrome 配置文件`

用户只需将 Switch Profile 设置为默认浏览器。它接收交给系统默认浏览器的 HTTP/HTTPS 链接，选择配置文件，并将原始 URL 转交给 Chrome。使用内置浏览器或明确指定其他浏览器的应用可能绕过此流程。

应用驻留在菜单栏中，在本地处理路由规则，无需后端服务或 GitHub/GitLab API。仓库访问权限沿用所选 Chrome 配置文件中已有的登录会话。

## 演示规则

仓库级规则优先于通用域名规则。

| 匹配条件 | Chrome 配置文件 | 验收链接 |
| --- | --- | --- |
| 主机名精确匹配 `git.fis.vn`，任意路径 | `khuepm18` | [GitLab 合并请求](https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests) |
| 主机名为 `github.com`，仓库路径 `/TruckerPoints/trucker-points` 及其子页面 | `khue@truckerpoints.ai` | [trucker-points](https://github.com/TruckerPoints/trucker-points) |
| 主机名精确匹配 `github.com` 的其他链接 | `pmkhue.2013` | [LumiBase](https://github.com/khuepm/LumiBase) |
| 其他主机名 | 用户选择的备用配置文件 | 任意其他网站 |

仓库规则涵盖 `/issues`、`/pull/123` 等页面，但不得匹配 `/TruckerPoints/trucker-points-other`。必须解析并匹配实际主机名，而非在整个 URL 中搜索字符串。保留原始路径、查询参数和 `#` 后的片段。

主机名按精确匹配处理。`www.github.com`、`api.github.com`、`gist.github.com` 或 `sub.git.fis.vn` 等子域名不匹配 GitHub 或 GitLab 规则，而是交给备用配置文件。

## 界面

- 默认浏览器状态及设置说明。
- 已检测到的 Chrome 配置文件，以及各规则的配置文件选择器。
- 备用配置文件选择器。
- URL 输入框、**Check rule**（检查规则）和 **Open test link**（测试打开）按钮。
- 配置文件不存在时的明确恢复选项。

配置文件的显示名称和邮箱地址不一定等于目录名称。应用映射到实际存在的目录，如 `Default` 或 `Profile 2`，不会猜测、修改登录数据或静默创建新配置文件。

## v0.2.0 包含的内容

1. 基于 AppKit 的原生 macOS 菜单栏应用，接收 HTTP/HTTPS URL 打开事件。
2. 顺序明确的仓库和域名规则、备用路由及循环防护。
3. 菜单栏入口、设置、配置文件映射和规则预览。
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

从菜单栏图标打开 **Settings…**。每条规则（R1 git.fis.vn、R2 trucker-points、R3 其他 github.com 链接、R4 备用）都有一个列出 Chrome 中已找到配置文件的选择器。

- 首次运行时，Switch Profile 会根据规则表中的身份为 R1–R3 自动识别配置文件，这些行显示 "Auto-detected: matched by …"。点击 **Confirm** 确认，或选择其他配置文件。
- **Detect** 按规则的身份重新查找。如果匹配到多个配置文件，应用不会自动选择，而是由你选择。
- R4 是所有其他主机名的备用配置文件，从不自动选择。若 R4 为 "Not set"，无关链接会在待处理链接窗口中等待。
- **Check rule** 显示某个 URL 对应的规则和配置文件，不会打开 Chrome。**Open test link** 通过真实的路由流程打开该 URL。
- 配置文件缺失或账号变更时，会在对应行和菜单中标记（"Profile mapping needs attention …"）。

配置保存在 `~/Library/Application Support/SwitchProfile/config.json`。若文件无效，菜单显示 "Configuration error – Reset to defaults…"。重置时会保留名为 `config.corrupt-<日期>.json` 的备份。

<!-- sp:default-browser -->
## 设为默认浏览器

在 Settings 中点击 **Set as default browser…**（菜单中也有 "Set as Default Browser…"），并确认 macOS 的提示。之后 Settings 会显示 Switch Profile 正在处理 `http` 和 `https`。

也可以在“系统设置”→“桌面与程序坞”→“默认网页浏览器”中选择。

<!-- sp:troubleshooting -->
## 故障排除

- **"Chrome profiles unavailable" / Local State 错误。** Switch Profile 读取 `~/Library/Application Support/Google/Chrome/Local State`。请确认 Chrome 已安装并至少启动过一次。在 macOS 27 上，系统可能拒绝应用读取该文件；请在“系统设置”→“隐私与安全性”中为 Switch Profile 授予访问权限（App Data 或“完全磁盘访问权限”），然后在 Settings 中点击 **Refresh**，或在待处理链接窗口中点击 **Refresh profiles**。
- **待处理链接窗口。** 暂时无法打开的链接（未设置配置文件、配置文件缺失、无法打开 Chrome）会被保留，不会丢弃。从菜单中的 "Pending links (n)…" 打开窗口，使用 **Open once**、**Open and use for R…**、**Retry** 或 **Discard**。
- **另一个副本是默认浏览器。** 如果 Settings 显示 "Another copy at … is the default; remove it."，请删除该副本，用 `lsregister -u <路径>`（完整路径见“卸载”）取消注册，然后重新设为默认。
- **Gatekeeper。** 应用为 ad-hoc 签名且未经公证。如果 macOS 阻止打开，请按住 Control 键点击应用并选择“打开”，或在“系统设置”→“隐私与安全性”中允许。
- **在终端中检查路由。** 试运行（dry run）会打印规则、配置文件目录和传给 Chrome 的确切参数，不会打开或写入任何内容：

  ```sh
  build/SwitchProfile.app/Contents/MacOS/SwitchProfile --dry-run [--assume-chrome running|closed] URL...
  ```

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

## 验收标准

- 从其他应用点击三个示例链接，均进入指定的配置文件。
- 即使前台是另一个 Chrome 配置文件的窗口，路由仍正确。
- Chrome 或 Switch Profile 尚未运行时也能正常打开链接。
- 其他域名使用明确选择的备用配置文件，不循环调用 Switch Profile。
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
