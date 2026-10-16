# WeChat 4.1.15.55（270135）适配

2026-10-16 安装时，原微信在退出后自动更新为本版本。版本保护检查阻止了旧版副本覆盖新版；用户选择保留并适配新版，因此新增本配置。

范围：Apple Silicon ARM64，普通静默防撤回和多开。没有在本版本中安装提示实验方案，没有增加禁止自动更新功能。

## 地址与证据

目标文件：Contents/Resources/wechat.dylib。
原版 ARM64 slice SHA256：`6a5bd0cbb39ad3092c15e9debda2db4969eedf1b58caad244d88033a996833a7`。

| 功能 | 地址 | 原字节 | 补丁字节 |
| --- | --- | --- | --- |
| 普通防撤回 | 0x4d1fb48 | 40100034 | 82000014 |
| 多开 | 0x286154 | FF0306D1FC6F14A9 | 20008052C0035FD6 |

撤回解析入口为0x4d1f8d8。0x4d1fb44调用0x48a94cc，该分类函数比较revokemsg。0x4d1fb48的条件分支改为跳往相同目标0x4d1fd50的无条件分支，跳过撤回分支解析。该位置与+0x7a0的newmsgid写入指令构成的双锚点在完整ARM64文件中唯一匹配。

多开检查函数使用bundleIdentifier、runningApplicationsWithBundleIdentifier:、count、firstObject、activateWithOptions:；它在实例数达到2时激活旧实例并返回false。唯一直接调用位于0x2ca6b8。本补丁让该检查返回true。

两处原始字节、分支目的地和配置内容已静态核验，并经独立只读复核。Tests/main.swift还使用交付配置，在相应真实偏移的稀疏合成文件上验证了写入。证据记录位于Tests/revoke-location-evidence-270135.json。

## 编译与签名修正

命令行程序已完整编译为ARM64独立可执行文件，官方swift-argument-parser1.6.2静态链接，无需运行时安装该依赖。

本机SwiftPM清单存在工具链ABI错误，因此此次使用swiftc直接构建依赖模块和主程序，并用临时VFS overlay避开本机重复SwiftBridging模块声明；没有改系统工具链。

实际副本测试发现原项目的签名流程不适用于新版微信：它不单独签资源库，清除全部扩展属性还会损坏以扩展属性存放的非Mach-O组件签名。已引入并注明来源的[Resigner实现](https://github.com/zengtianli/WeChatTweak/blob/master/Sources/WeChatTweak/Resigner.swift)：保留原权限、为本地签名代码补充必要执行权限、先签资源库、再签整包并恢复权限、仅尝试删除quarantine属性、最后严格验证整个应用。另修复子进程stderr管道可能阻塞的问题，采用临时文件接收stderr。

包内启动器默认选择随包config.json，不访问上游远程配置。用户显式指定--config时仍使用其指定值。

## 验证边界

签名通过或程序成功启动不能证明聊天防撤回已通过实测。没有自动向任何联系人发送或撤回消息；需要用户自行用一条测试消息确认效果。自动更新整包会覆盖补丁，更新后需要重新检查版本适配。
