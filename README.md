# WeChatTweak · 4.1.15 适配版

本项目基于 **[sunnyyoung/WeChatTweak](https://github.com/sunnyyoung/WeChatTweak)** 二次开发、升级和更新，保留上游 Git 提交历史与 AGPL-3.0 许可证。感谢原作者 sunnyyoung 及上游贡献者。

本分支主要新增 macOS 微信 **4.1.15.11 / 4.1.15.55 的 Apple Silicon（ARM64）适配**，提供普通静默防撤回、多开，以及保留微信原生撤回提示的实验配置；同时改进新版微信的补丁目标选择、原始字节校验和重新签名流程。这是独立维护的衍生版本，与腾讯官方无关，也不是上游官方发布版本。

> 当前默认配置为「普通静默防撤回 + 多开」。带提示模式需要显式选择实验配置。2026-10-16，用户反馈 4.1.15.55（270135）ARM64 提示模式私聊实测成功：原消息保留，撤回提示正常显示。用户另反馈群聊可保留被撤回的消息，但不显示撤回提示。上述结果不代表所有消息类型或系统环境均已覆盖。

## 目录

- [支持范围与验证状态](#支持范围与验证状态)
- [与上游的区别](#与上游的区别)
- [安装与编译](#安装与编译)
- [使用前准备](#使用前准备)
- [应用普通模式](#应用普通模式)
- [应用原生提示实验模式](#应用原生提示实验模式)
- [打开第二个微信](#打开第二个微信)
- [切换回普通模式与恢复原版](#切换回普通模式与恢复原版)
- [常见问题](#常见问题)
- [开发与测试](#开发与测试)
- [来源致谢与许可证](#来源致谢与许可证)

## 支持范围与验证状态

| 微信版本 | 内部构建号 | 本次新增架构 | 普通防撤回配置 | 原生提示配置 | 验证状态 |
| --- | --- | --- | --- | --- | --- |
| 4.1.15.55 | 270135 | ARM64 | 有 | 实验 | 两种模式均已核验补丁字节、严格签名与启动；普通模式已验证两个主进程同时运行；用户反馈：提示模式私聊保留消息且显示提示；群聊保留消息但无撤回提示 |
| 4.1.15.11 | 270091 | ARM64 | 有 | 实验 | 静态定位、合成文件补丁和副本重签名验证；未完成聊天实测 |

`config.json` 还保留上游原有的 31927、32281、32288、31960、34371 配置。本分支未重新验证这些历史版本，不据此承诺它们在当前系统上的运行效果。

- 此次新增配置仅支持 **Apple Silicon Mac**，未新增对应版本的 Intel / x86_64 适配。
- 工具源码要求 macOS 12 或更高版本；微信本身的系统要求仍以微信为准。
- 本次两个 4.1.15 构建的配置没有加入「阻止自动更新」。微信更新可能覆盖补丁。
- 版本匹配使用 **CFBundleVersion（内部构建号）**，不能只看显示版本号。

## 与上游的区别

1. 新增 270091、270135 的撤回处理与多开补丁地址，并保存定位证据。
2. 配置可选择 `Contents/Resources/wechat.dylib`；兼容上游默认的 `Contents/MacOS/WeChat`。
3. 补丁条目支持 `expected` 原始字节校验；先检查全部条目，再执行写入，避免因后续条目不匹配而留下部分修改。磁盘写入失败仍不具备事务回滚能力。
4. 新版签名流程单独签署已修改的资源库，保留和恢复需要的原权限、补充本地签名执行权限，并严格验证整个应用；不会要求关闭 SIP。
5. 提供独立原生提示实验配置、270135 完整静默回退配置，以及合成 Mach-O 回归测试。

## 安装与编译

### 从本仓库源码编译（推荐）

先安装 Apple Xcode Command Line Tools（已安装可跳过）：

```bash
xcode-select --install
```

然后下载源码并编译，需要 Swift 6 工具链及网络连接以获取依赖：

```bash
git clone https://github.com/pyy-Yanis/WeChatTweak-4.git
cd WeChatTweak-4
swift build -c release --arch arm64
```

后续示例默认在仓库根目录执行，工具路径是 `.build/release/wechattweak`。

**不要用 `brew install sunnyyoung/tap/wechattweak` 代替本分支的编译。** 该命令安装上游版本，不包含这里的修改。

### 使用预编译工具包

若本仓库 [Releases](https://github.com/pyy-Yanis/WeChatTweak-4/releases) 提供 ARM64 工具包，可下载解压，在解压目录运行：

```bash
chmod +x ./wechattweak ./libexec/wechattweak
./wechattweak --help
./wechattweak versions
```

预编译包外层 `wechattweak` 启动器默认读取包内 `config.json`；显式指定 `--config` 时使用指定配置。请阅读该包的 README，确认它默认是普通模式还是提示实验模式。

从源码编译的原始可执行文件仍保留上游远程默认配置 URL，因此下文始终显式传入本地 `--config`，确保使用本分支的适配。

## 使用前准备

`patch` 会修改指定微信应用内的程序，并对应用重新签名。它不是仅修改配置文件的操作。

1. 查看版本信息：

   ```bash
   /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/WeChat.app/Contents/Info.plist
   ```

2. **退出全部微信实例。** 多开时，每个实例都需要退出。
3. 备份完整原版应用，例如首次备份时运行：

   ```bash
   mkdir -p "$HOME/Documents/WeChatTweak-backup"
   ditto --rsrc --extattr /Applications/WeChat.app "$HOME/Documents/WeChatTweak-backup/WeChat.app"
   ```

   如果该备份目录已存在，请另选新目录，避免覆盖原始备份。应用备份不包含聊天数据；聊天数据需要自行另行备份。

4. 若微信退出后发生自动更新，请重新核对构建号。未知版本不要复用旧补丁地址。

默认应用位置为 `/Applications/WeChat.app`；安装在其它位置时，请修改命令中的 `--app` 路径。应用目录需要当前用户可写；遇到权限错误时先确认目录所有权与安装位置。

## 应用普通模式

查看本地配置支持的构建号：

```bash
.build/release/wechattweak versions --app /Applications/WeChat.app --config ./config.json
```

退出全部微信并完成备份后，执行：

```bash
.build/release/wechattweak patch --app /Applications/WeChat.app --config ./config.json
```

270135 和 270091 的默认条目为「普通静默防撤回 + 多开」：跳过撤回解析分支，因此通常不会产生撤回提示；实际消息保留效果仍需验证。

检查签名并启动：

```bash
codesign --verify --deep --strict /Applications/WeChat.app
open /Applications/WeChat.app
```

若之前已经使用提示实验模式，请按下文「切换回普通模式」操作，不要直接用此处的默认配置切换。

## 应用原生提示实验模式

### 微信 4.1.15.55 / 270135

```bash
.build/release/wechattweak patch --app /Applications/WeChat.app --config ./config-4.1.15.55-keeptip.json
```

### 微信 4.1.15.11 / 270091

```bash
.build/release/wechattweak patch --app /Applications/WeChat.app --config ./config-4.1.15.11-keeptip.json
```

运行前仍需退出全部实例并备份。配置支持从原版或本分支的普通模式切换，保留多开。

实验模式保留撤回 XML 和微信原生提示文本的解析，只把用于后续处理的 `newmsgid` 写入改为零，尝试在避免原消息删除的同时保留微信原生提示。它不注入自定义提示消息，也不保证具体文案。

**测试方法：** 用另一账号在私聊发送一条不重要的新消息，然后从另一端撤回；分别检查「原消息是否仍在」「撤回提示是否出现」。私聊通过后再测试群聊。目前用户实测群聊可保留被撤回的消息，但不显示撤回提示，这是当前已知限制。若原消息仍被删除或出现其它异常，请记录具体场景并切回普通模式。

**用户实测反馈（2026-10-16）：** 4.1.15.55（270135）ARM64 原生提示模式在私聊中可保留被撤回的消息，并正常显示撤回提示。该反馈来自用户测试，维护者未自行收发消息验证；用户随后反馈群聊也能保留被撤回的消息，但没有撤回提示。群聊提示目前不支持；其它消息类型及长期使用尚未全面验证，因此暂保留实验标记。详细机制见 [提示模式说明](ADAPTATION-4.1.15.55-keeptip.md)。

## 打开第二个微信

第一个微信运行后，在终端执行：

```bash
open -n /Applications/WeChat.app
```

在新窗口登录另一个账号。本地验证仅确认普通模式下两个微信主进程能同时运行，尚未验证所有账号登录、数据隔离和长期运行场景。

## 切换回普通模式与恢复原版

### 270135：从提示实验模式切回静默模式

退出全部微信实例，执行：

```bash
.build/release/wechattweak patch --app /Applications/WeChat.app --config ./config-4.1.15.55-silent-restore.json
```

该配置同时恢复 `newmsgid` 存储和静默分支，并保留多开。**只重新应用原默认配置不会完整撤销提示实验模式的所有修改。**

270091 暂未提供同等的独立完整回退配置；需要回退时应恢复原版应用，再应用普通配置。

### 恢复完整原版应用

退出全部微信，先将当前应用移到其它目录，再将之前完整备份的 `WeChat.app` 复制回 `/Applications`。恢复后核对版本并执行签名检查。不需要删除聊天数据目录。

如果微信已经更新，不要未经确认就用旧版本备份覆盖新版本；应先确认版本和数据兼容情况。

## 常见问题

### 录屏权限已开启，截图仍提示未授权

重新签名后，系统记录的原授权可能需要刷新。退出所有微信，在「系统设置 → 隐私与安全性 → 屏幕录制 / 屏幕与系统音频录制」关闭再开启微信权限，然后重新启动。

仍无效时，可在退出微信后仅重置微信的录屏授权：

```bash
tccutil reset ScreenCapture com.tencent.xinWeChat
```

重新启动微信并触发截图，按系统提示重新授权。此操作重置的是录屏权限，不会删除聊天记录。若仍失败，请提供 macOS 版本和提示内容进一步排查。

### Unsupported WeChat version

先确认内部构建号，再检查是否显式传入本仓库本地配置。本次只新增 270091 和 270135，未知版本需要重新定位与验证。

### 原始字节不匹配 / unexpectedBytes

工具发现目标与预期不符，会在写入前拒绝该轮补丁。可能是版本不符、其它补丁修改过程序，或配置选错。不要删除 `expected` 来强行运行；应恢复已知原版并重新核对。

### 签名失败或打补丁后不能启动

保留命令的完整错误输出，优先恢复完整备份，不要继续叠加不明补丁。本项目不会要求关闭系统 SIP 或 Gatekeeper。重新签名可能影响录屏、钥匙串、应用组等系统授权或功能，启动成功也不代表所有功能正常。

### 微信更新后功能消失

更新会覆盖程序文件和补丁。核对新构建号后再决定是否重新应用；本分支未对本次新增版本禁用自动更新。

### 本地 Swift 工具链编译失败

源码使用标准 SwiftPM 构建。当前开发机器曾遇到 SDK 模块重复与 PackageDescription ABI 错误；交付工具使用同一源码和锁定的 ArgumentParser 1.6.2 直接编译并静态链接依赖。该本地绕过方式不作为通用安装步骤。遇到相同错误，先检查 `swift --version`、`xcode-select -p` 和所选 SDK 是否匹配，不要直接修改系统工具链文件。

## 开发与测试

```bash
sh Tests/run.sh
```

测试使用合成 thin/FAT Mach-O 文件，不运行微信，也不读取聊天数据。覆盖：旧配置兼容、目标路径白名单、地址换算、切片隔离、重复应用、原始字节拒绝、后续条目不匹配时不部分写入、270091/270135 配置以及 270135 提示/静默切换；另有签名权限转换检查。

定位与变更说明：

- [4.1.15.55 适配](ADAPTATION-4.1.15.55.md)
- [4.1.15.55 提示实验模式](ADAPTATION-4.1.15.55-keeptip.md)
- [4.1.15.11 早期适配记录](ADAPTATION-4.1.15.11.md)（历史记录，当前状态以本 README 为准）
- `Tests/revoke-location-evidence-270135.json`、`Tests/keeptip-evidence-270135.json`：静态定位证据。

`Tests/verify_270091.py` 只读检查指定的 270091 原版资源库或 ARM64 切片；不要用于 270135 或已打补丁的文件。

提交问题时请附上 macOS 版本、微信显示版本和内部构建号、CPU 架构、使用的配置、报错内容及复现步骤。请勿上传聊天记录、登录凭据或完整微信程序。

## 来源、致谢与许可证

- **主要上游：[sunnyyoung/WeChatTweak](https://github.com/sunnyyoung/WeChatTweak)**。本项目在其源码基础上二次开发并进行版本适配，原有权利与署名保留。
- [zengtianli/WeChatTweak](https://github.com/zengtianli/WeChatTweak)：参考撤回定位方法与新版重签名实现；`Resigner.swift` 标明了来源，并修复了子进程 stderr 管道可能阻塞的问题。
- [fzlzjerry/wechat-antirecall](https://github.com/fzlzjerry/wechat-antirecall)：参考原生提示实验补丁的思路。
- [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser)：命令行参数解析依赖。

本项目遵循 [GNU AGPL-3.0](LICENSE)。分发修改版或二进制时，请保留许可证、来源说明，并依照许可证提供对应修改源码；依赖项保留各自许可证。本仓库不包含微信应用、聊天数据或腾讯程序二进制文件。
