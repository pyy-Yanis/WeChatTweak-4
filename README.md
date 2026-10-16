# WeChatTweak-4

基于 **[sunnyyoung/WeChatTweak](https://github.com/sunnyyoung/WeChatTweak)** 二次开发、升级更新的 macOS 微信工具，保留上游 Git 历史、署名和 [AGPL-3.0 许可证](LICENSE)。本项目独立维护，与腾讯官方无关。

主要新增微信 **4.1.15.11 / 4.1.15.55 的 Apple Silicon（ARM64）适配**，提供防撤回、原生撤回提示和多开，并改进补丁字节检查与重新签名流程。

## 当前状态

| 微信版本 | 构建号 | 默认模式 | 验证结果 |
| --- | --- | --- | --- |
| 4.1.15.55 | 270135 | `tip`：私聊、群聊提示 + 多开 | 用户实测消息保留及提示正常，提示不重复、发送者正确；签名、启动和模式切换测试通过 |
| 4.1.15.11 | 270091 | `tip`：原生提示实验模式 + 多开 | 静态定位、合成补丁与副本签名检查；未完成真实聊天验证，群聊提示不保证 |

以上聊天结果来自用户实测反馈（2026-10-16），维护者未自行收发消息；其它消息类型、自己撤回及长期使用尚未全面验证。270135 的结果不能推广到其它构建或系统环境。

- 新增适配只支持 **Apple Silicon / ARM64**，没有新增对应版本的 Intel 配置。
- 工具最低为 macOS 12；微信本身的系统要求仍以微信为准。
- 保留上游 31927、32281、32288、31960、34371 的配置及原行为，未重新验证这些历史构建。
- 本次新增版本不包含禁止自动更新功能；微信更新会覆盖补丁。

## 一个配置文件，按模式使用

所有版本和模式统一保存在根目录 **`config.json`**，无需挑选多个配置文件。

| 参数 | 270135 / 4.1.15.55 | 270091 / 4.1.15.11 |
| --- | --- | --- |
| 不传 `--mode` | 默认 `tip` | 默认 `tip`，仍为实验状态 |
| `--mode tip` | 私聊、群聊防撤回提示 + 多开 | 原生提示实验模式 + 多开 |
| `--mode silent` | 静默防撤回 + 多开，完整恢复提示相关分支 | 静默防撤回 + 多开，恢复提示相关写入 |
| `--mode private-tip` | 回退旧提示方式：私聊有提示、群聊静默 + 多开 | 不支持 |

历史构建未新增模式，省略 `--mode` 或传 `silent` 均沿用原配置。未知模式会在写入前报错，不会自动切换为其它模式。

配置结构为：每个版本一个条目；`targets` 保存共享补丁（新增版本为多开），`modes` 保存各模式补丁，`defaultMode` 指定默认模式。命令行先选中模式，再将模式补丁和共享补丁交给补丁器。旧版不含 `modes` 的配置继续兼容。

**新配置需要使用本分支新版工具。** 旧工具不认识 `modes`，不能只下载新 `config.json` 配合旧二进制使用。此前包中分散的配置文件已合并，旧文件名不再是新版用法。

## 编译

安装 Xcode Command Line Tools（已安装可跳过）：

```bash
xcode-select --install
```

需要 Swift 6 工具链及用于获取依赖的网络连接：

```bash
git clone https://github.com/pyy-Yanis/WeChatTweak-4.git
cd WeChatTweak-4
swift build -c release --arch arm64
```

以下命令均在仓库根目录执行，工具位置为 `.build/release/wechattweak`。

`brew install sunnyyoung/tap/wechattweak` 安装的是上游版本，不包含本分支的配置整理和新增适配，不能替代上述编译。

如果 [Releases](https://github.com/pyy-Yanis/WeChatTweak-4/releases) 提供匹配的预编译工具包，解压后可使用包内 `./wechattweak` 替换示例中的 `.build/release/wechattweak`。包内启动器会默认选用随包 `config.json`；显式传入 `--config` 时使用指定文件。

## 打补丁前

`patch` **会修改并重新签名微信应用**。退出全部微信实例，保留完整应用备份，再执行补丁。

查看内部构建号（版本判断使用此值，不只看显示版本号）：

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/WeChat.app/Contents/Info.plist
```

首次备份的示例：

```bash
mkdir -p "$HOME/Documents/WeChatTweak-backup"
ditto --rsrc --extattr /Applications/WeChat.app "$HOME/Documents/WeChatTweak-backup/WeChat.app"
```

如果备份已存在，请另选新目录，避免覆盖原版。应用备份不包含聊天数据，聊天记录需自行另行备份。微信退出时可能自动更新，打补丁前应再次核对构建号。

## 开启防撤回和提示

查看版本及可选模式：

```bash
.build/release/wechattweak versions --config ./config.json
```

默认开启带提示模式和多开：

```bash
.build/release/wechattweak patch --app /Applications/WeChat.app --config ./config.json
```

也可明确指定：

```bash
.build/release/wechattweak patch --app /Applications/WeChat.app --config ./config.json --mode tip
```

签名检查与启动：

```bash
codesign --verify --deep --strict /Applications/WeChat.app
open /Applications/WeChat.app
```

原始可执行文件默认从本 Fork 的远程 `config.json` 加载配置。示例显式使用本地配置，便于确认正在应用哪一版配置。应用不在默认位置时修改 `--app` 路径；目标目录需当前用户可写。

## 切换与回退

每次切换前退出全部微信实例。模式内包含完整恢复指令，可以从本分支之前的提示/静默/群聊提示状态切换，也允许重复应用同一模式。

切回静默：保留消息，不显示撤回提示。

```bash
.build/release/wechattweak patch --app /Applications/WeChat.app --config ./config.json --mode silent
```

270135 回退旧提示方案：私聊有提示，群聊静默。

```bash
.build/release/wechattweak patch --app /Applications/WeChat.app --config ./config.json --mode private-tip
```

恢复完整原版：退出全部微信，将当前应用移到其它目录，再把完整原版备份复制回 `/Applications`，最后核对版本和签名。不要删除聊天数据目录。若微信已经更新，不要未经确认用旧版备份覆盖新版。

## 多开

第一个微信打开后，在终端执行：

```bash
open -n /Applications/WeChat.app
```

在新窗口登录另一个账号。已验证两个主进程同时运行；没有覆盖全部账号登录、数据隔离和长期运行场景。

## 测试实际效果

用另一账号发送一条不重要的新消息并撤回，分别确认原消息保留、提示出现、归属正确且不重复。私聊和群聊分别测试；图片、文件、自己撤回等场景需要单独确认。

模式切换及签名通过不等于聊天行为验证。出现异常时可以切回 `silent` 或恢复完整原版备份。不要上传聊天记录、登录凭据或完整微信程序来反馈问题。

## 常见问题

### 录屏权限已开，截图仍提示未授权

重新签名后可能需要刷新原授权。退出全部微信，在「系统设置 → 隐私与安全性 → 屏幕录制 / 屏幕与系统音频录制」关闭再开启微信权限，重新启动。

仍无效时，退出微信后仅重置微信录屏授权：

```bash
tccutil reset ScreenCapture com.tencent.xinWeChat
```

重新打开微信并触发截图，按系统提示授权。此命令不删除聊天记录。

### Unsupported version / Mode is not supported

核对内部构建号、配置文件和模式。未知版本需要重新定位；不支持的模式不会回落到默认模式。

### unexpectedBytes / 原始字节不匹配

目标程序可能与预期版本不符，或被其它工具改过。补丁器先检查所有条目，再执行写入；不匹配则拒绝该轮操作。不要删除 `expected` 强行运行。磁盘写入失败不具备事务回滚能力，仍需完整备份。

### 签名失败或不能启动

保留错误输出并优先恢复备份。重新签名可能影响录屏、钥匙串、应用组等系统授权或功能，启动成功也不代表所有功能正常。不需要关闭 SIP 或 Gatekeeper。

### 微信升级后失效

更新覆盖补丁；核对新构建号，只有明确适配才重新应用。不能把旧地址强行应用到未知版本。

### Swift 编译失败

检查 `swift --version`、`xcode-select -p` 和所选 SDK 是否匹配。本开发机遇到过模块重复与 SwiftPM 清单 ABI 问题，本地工具使用相同源码直接编译并静态链接锁定的 ArgumentParser 1.6.2；这种本机绕过方式不作为通用安装步骤，不要修改系统工具链文件。

## 开发与验证

```bash
sh Tests/run.sh
```

测试仅使用合成 Mach-O 和权限数据，不启动微信、不读写聊天，覆盖旧配置兼容、模式默认值、未知模式拒绝、路径白名单、thin/FAT 地址换算、原字节校验、重复应用、跨模式完整恢复和签名权限转换。

- [版本适配与补丁位置](docs/ADAPTATION.md)
- [群聊原生提示机制](docs/GROUP-TIP.md)
- `Tests/*evidence*.json`：静态定位证据，不是运行时配置。
- `Tests/verify_270091.py`：只读核对 270091 原版资源库或切片，不能用于其它构建或已打补丁文件。

本仓库仅有一个运行时配置文件 `config.json`。修改模式时应同时更新测试，尤其确认其它模式的旧指令能被完整恢复。

## 来源、致谢与许可证

- **[sunnyyoung/WeChatTweak](https://github.com/sunnyyoung/WeChatTweak)**：主要上游，本项目在其源码基础上二次开发升级。
- [zengtianli/WeChatTweak](https://github.com/zengtianli/WeChatTweak)：参考定位方法和新版签名实现，`Resigner.swift` 保留来源署名，并修复 stderr 管道可能阻塞的问题。
- [fzlzjerry/wechat-antirecall](https://github.com/fzlzjerry/wechat-antirecall)：参考原生提示实验思路。
- [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser)：命令行解析依赖。

遵循 [AGPL-3.0](LICENSE)。分发修改版和二进制时，保留许可证、来源说明并依许可证提供对应源码；依赖保留各自许可证。本仓库不包含微信应用或聊天数据。
