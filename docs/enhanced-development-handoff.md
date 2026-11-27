# RustDesk Enhanced 开发交接

## 接手基线

当前维护分支是 `shuhangli-enhance`，本次交接对应代码提交 `adf54a59b`。对照基线是上游 RustDesk 标签 `1.5.3`（`95cca3f66`），由 `b0dd50234` 合入增强分支。最初的 iOS 增强从 1.5.0 开始，已在合并前进入分支。查看完整定制内容时从 `1.5.3` 开始比较，查看升级后的迭代时从 `b0dd50234` 开始。

```powershell
git status -sb
git log --first-parent --oneline 1.5.3..HEAD
git diff --stat 1.5.3 HEAD
git diff 1.5.3 HEAD -- . ':(exclude)src/lang'
```

基线到交接提交共有 149 个变更文件，其中 54 个为 `src/lang/` 本地化文件。`libs/hbb_common` 在两端都指向 `fae47e024dd83cef6aaecde0aa7d11731df11649`。这批功能部署在 RustDesk 应用两端，继续使用现有 hbbs/hbbr。iOS 与 Android 使用相同的移动端触控、窗口专注和本地画质代码，前两项依赖带相应能力的 Windows 被控端。Tailnet、首页、方向、宏、密码自动填充和 PiP 是 iOS 专属功能。

## 功能与代码入口

### iOS 首页、方向、工具栏和键盘宏

- `device_home.dart` 提供地址簿、收藏、最近连接和在线设备等入口，`session_toolbar.dart` 提供浮动会话操作，两项默认开启，可在增强设置中关闭。普通移动首页、设置和会话页接入这些入口；连接页的原有设备操作继续复用。`orientation.dart` 排队处理进入、退出和手动旋转，iPhone 默认在会话进入时请求横屏，iPad 默认不限制方向。关闭会话内的画布手势会保留当前画布变换，该偏好会持久化。[iOS 模块](../flutter/lib/mobile/ios/) · [移动端页面](../flutter/lib/mobile/pages/)
- 宏使用 `ios-keyboard-macros` 保存按键组合和逐步延时，通过现有键盘消息执行。会话关闭、应用退后台、用户停止或失去键盘权限时取消剩余步骤。发送完成表示按键已发出，目标应用的执行结果需在远端检查。相关提交为 `1330a701a`、`477e125d3`、`32c95877d`、`684e0f1ed`。[宏存储和执行](../flutter/lib/mobile/ios/keyboard_macro.dart) · [会话宏入口](../flutter/lib/mobile/ios/session_macros.dart)

### iOS 密码自动填充

Console 账号表单把用户名和密码放进同一个原生 AutoFill 组，远程设备访问密码使用独立组。关闭表单取消上下文。Console 用户名密码登录成功且 token 已保存时，只有表单仍打开、输入仍与提交值一致才请求系统保存。设备连接、OIDC、跳转二步验证的原密码表单均不提交保存请求，远程 OS 凭据继续走原输入路径。修改点主要是 `login.dart` 和 `dialog.dart` 的共享包装层，并由 `password_autofill.dart` 限定到原生 iOS。主要提交为 `e507971c3`。[登录组件](../flutter/lib/common/widgets/login.dart) · [对话框](../flutter/lib/common/widgets/dialog.dart) · [自动填充测试](../flutter/test/password_autofill_test.dart) · [验收说明](ios-password-autofill.md)

### iOS 内嵌 Tailscale 和 Headscale

- Tailnet 总开关默认关闭。启用后默认只分流匹配配置的 Console API，ID 和 Relay 需分别开启。Headscale 控制服务器地址与 RustDesk 服务地址独立配置，变更控制服务器会重置本机节点身份，需重新授权。Swift 管理 Keychain 与生命周期，Go `tsnet` 保存加密状态并持有本机受限转发器。远控页面或 PiP 持有会话期间，退后台暂停轮询并保留 Tailnet，恢复前台先查询原生状态。主要提交为 `1330a701a`、`5e5bfbfce`、`4341750cf`。[Dart 状态和设置](../flutter/lib/mobile/ios/tailnet.dart) · [Swift 控制器](../flutter/ios/IosEnhancements/Classes/IosEnhancements.swift) · [Go 模块](../libs/ios_tailnet/)
- API 路径从 Flutter HTTP 入口转到 Rust，再经过仅匹配配置 origin 的本地代理。HTTPS 证书仍由 Rust 验证。ID、Relay 和在线查询走各自固定目标的 TCP 转发，ID 分流还影响 NAT 探测、WebRTC 发起和中继策略。备用服务器需显式启用，可能收到账号凭据。上游合并时优先核对新增的 HTTP、OIDC 和 rendezvous 调用是否接入已有分流入口。[Flutter HTTP](../flutter/lib/utils/http_service.dart) · [Rust 分流](../src/platform/ios_tailnet.rs) · [HTTP 路径](../src/common.rs) · [会话连接](../src/client.rs) · [账号和 HTTP 客户端](../src/hbbs_http/)

### iOS 原生画中画

远控工具栏提供手动开关，自动 PiP 默认开启并受系统设置影响。Rust 视频线程将现有解码 BGRA 帧交给 Swift 的 `AVSampleBufferDisplayLayer`，复用当前连接、显示器和裁切范围。自动档正常模式下限制在最长边 960 像素、15 帧/秒，低电量使用节能档。确认传输中断后由原有重连流程负责有限次数的恢复。`Info.plist` 声明 `audio` 后台模式，锁屏、切网或宿主挂起后的持续时间要用目标设备测量。主要提交为 `7007e221a`、`32ef03720`。[Dart PiP 控制](../flutter/lib/mobile/ios/picture_in_picture.dart) · [Rust 帧出口](../src/platform/ios_pip.rs) · [Swift PiP 和帧处理](../flutter/ios/IosEnhancements/Classes/)

### 移动端控制 Windows

- **原生触控。** iOS 和 Android 的工具栏在触控、鼠标、Windows 原生触控之间切换。原生模式要求 Windows 被控端通告 `native_touch` 并允许键鼠操作。偏好以 `windows-native-touch` 按设备保存。`NativeTouchContact` 携带有符号桌面坐标，Windows 端通过系统 API 最多注入 10 个活动触点。切换模式、撤权、退后台和断连都应检查触点清理。安全桌面等无法注入的场景可用原有鼠标模式。主要提交为 `006cd9f8d`、`adf54a59b`。[移动输入](../flutter/lib/mobile/widgets/windows_touch.dart) · [Windows 触控注入](../src/platform/windows_touch.rs)
- **窗口专注。** Windows 端通告 `remote_window_focus`，有键鼠权限时可从显示按钮旁的图标选窗口。选择窗口会请求恢复最小化窗口并将其切到前台。打开选择器或专注期间每秒查询快照，被控端按连接限流并仅在默认交互桌面枚举。手机从现有桌面流裁切窗口，支持完整显示、铺满和拉伸；触点、鼠标、滚轮、光标与 PiP 裁切使用同一套桌面几何。跨屏使用可见面积最大的显示器区域，遮挡仍按桌面流显示，窗口关闭或最小化后退出专注。主要提交为 `d89ff3543`、`dd9d58d84`、`6dcc2d376`、`36edb49e7`。[控制器和视图](../flutter/lib/mobile/widgets/remote_window_focus.dart) · [坐标变换](../flutter/lib/models/window_focus_geometry.dart) · [Windows 枚举和激活](../src/platform/windows_focus.rs)
- **消息路径。** 两项功能复用 Flutter 的 `sessionSendPointer`，经 Rust `src/flutter.rs`、`src/ui_session_interface.rs` 和 `libs/base/protos/message.proto` 到 Windows 的连接和输入服务。窗口快照经 `src/client/io_loop.rs` 回到 Dart 模型。窗口专注点击复用 `session_send_mouse` 的可选 `focus_x`、`focus_y`，先定位再发点击。旧被控端缺能力时保留原有输入，窗口专注入口提示升级或授予键鼠权限。[协议](../libs/base/protos/message.proto) · [发送和事件派发](../src/flutter.rs) · [Windows 连接处理](../src/server/connection.rs) · [Flutter 会话模型](../flutter/lib/models/model.dart)

### 移动端本地画质

默认关闭。普通增强使用 Flutter 高质量采样，AI 超分使用内嵌着色器进行 2 倍重建。处理区域限于当前画面或窗口裁切，原帧优先绘制，只有与当前帧及区域一致的结果才会显示。区域过大、着色器不可用或耗时超过阈值时使用普通采样，后台停止提交推理。现有训练评估使用合成边缘和笔画，真机画质、时延与功耗要分开评估。主要提交为 `9b97a3cb7`。[画质实现](../flutter/lib/mobile/widgets/mobile_video_quality.dart) · [着色器](../flutter/shaders/mobile_super_resolution.frag) · [权重训练脚本](../scripts/train_mobile_super_resolution.mjs)

## 构建、打包和本地验证

- **统一入口。** 手动运行 `Enhanced Build`，选择 iOS、Windows 或两者；至少选一个，构建 iOS 时需填写独立 Bundle ID。它复用同一运行中的 `bridge-artifact`，各平台也可以单独手动构建。手动入口依赖工作流文件存在于 GitHub 默认分支。按仓库规则使用与目标提交对应的原生 bridge 产物，本地不要运行 `flutter_rust_bridge_codegen`。[统一工作流](../.github/workflows/enhanced-build.yml) · [Bridge 工作流](../.github/workflows/bridge.yml) · [仓库开发规则](../AGENTS.md)
- **iOS。** Enhanced CI 固定 Flutter 3.24.5、Rust 1.75、Go 1.26.5、Xcode 16.4 和 `macos-15`。当前 Xcode 工程和 Podfile 的最低目标为 iOS 15.0。先生成真机 ARM64 `libEmbeddedTailnet.a` 和许可证清单，再用 `cargo rustc --locked --features flutter,hwcodec --release --target aarch64-apple-ios --lib --crate-type staticlib` 生成 Rust 库，由 Xcode 链接。现有脚本提供真机 slice。`unsigned` 产出供 LiveContainer 或重签名的 IPA，`development`、`ad-hoc`、`app-store` 需要匹配证书与 profile。构建脚本使用独立 Bundle ID 和原有 RustDesk 图标，CI 校验实际 IPA 内的 iPhone/iPad 图标。上游 `flutter-build.yml` 的 iOS job 也接入了 Go 静态库，合并上游时要保留。旧功能文档中的 1.5.0 是开发起点，AutoFill 文档中的 iOS 13.0 是当时的部署目标说明。[iOS 工作流](../.github/workflows/ios-enhanced.yml) · [Podfile](../flutter/ios/Podfile) · [原有平台工作流](../.github/workflows/flutter-build.yml) · [本地 iOS 构建和签名说明](ios-enhanced.md#github-actions)
- **Windows。** `Windows Enhanced` 使用 `windows-2022`、x64 vcpkg、Flutter 3.24.5/Rust 1.75 及上游 Flutter 补丁。`portable` 上传 `windows-enhanced-x64-unsigned`，包含可运行的目录包；`setup` 复用上游 WiX 工程，上传 `windows-enhanced-x64-setup-unsigned`。两种产物均未签名。关键提交为 `a97970ac1`、`98bf5cf51`、`d4c39a2fc`。[Windows 工作流](../.github/workflows/windows-enhanced.yml) · [MSI 工程](../res/msi/)
- **Flutter 依赖。** `pubspec.yaml` 增加着色器资源。当前提交的 `pubspec.lock` 声明 Dart `>=3.8.0-0 <4.0.0`，而 Enhanced CI 用 Flutter 3.24.5。切换 SDK 后先按工作流执行 `flutter pub get`，核对解析结果和锁文件差异，再运行测试。本工作区 PATH 上的 Flutter 是 3.35.6，历史文档记录它和现有 `extended_text` 的兼容问题。[Flutter manifest](../flutter/pubspec.yaml) · [锁文件](../flutter/pubspec.lock)

在仓库根目录运行 Rust 测试，在 `libs/ios_tailnet` 运行 Go 测试，在 `flutter` 运行 Flutter 测试。

```powershell
cargo test --locked --offline -p base --lib
go test -count=1 ./...
flutter pub get
flutter test --no-pub
```

## 验证状态与接手后的验收

- **本次复跑。** `base` 单测 19 项通过，3 项需要 Windows 符号链接权限而跳过。Go 完整套件的 `TestProxyUsesTailnetDialAndPreservesResponse` 返回 502，独立的回环连接验证也被当前沙盒拒绝。跳过这一项后其他 Go 测试通过，完整套件仍需在允许回环的环境重跑。Flutter 定向复跑未得到测试结果。
- **历史记录。** Flutter 全量测试 202 项通过、1 项跳过，Go 测试和 `go vet` 曾通过。历史 Windows 环境的完整 Flutter/Rust 构建缺少 Opus 和 libvpx 头文件。`adf54a59b` 的 GitHub Actions 产物、安装和真机闭环需单独确认。[历史验证记录](ios-enhanced.md#本地验证与真机验收)
- **回归用例入口。** 输入模式用 `mobile_pointer_mode_test.dart`，窗口专注用 `window_focus_geometry_test.dart` 与 `window_focus_unavailable_test.dart`，画质用 `mobile_super_resolution_test.dart`。iOS 的主要用例在 `ios_tailnet_test.dart`、`ios_orientation_test.dart`、`ios_keyboard_macro_test.dart`、`ios_session_macro_menu_test.dart` 和 `password_autofill_test.dart`。[Flutter 测试目录](../flutter/test/)

1. 从同一个增强提交构建 IPA 和 Windows x64 包。保留运行链接、SHA、签名模式和产物名称；先启动便携版，再验证 MSI 安装、服务启动和卸载。iOS 分别验证签名安装与 LiveContainer 导入，记录 Bundle ID 和 `CFBundleVersion`。
2. 用 iPhone 和 iPad 验证 Tailnet 关闭路径、Headscale 授权、Console 登录与地址簿、按需开启 ID/Relay 分流。在活动画面下测 PiP 自动与手动切换、后台返回、锁屏、Wi-Fi/蜂窝切换。结合 `Remote PiP`、`iOS Tailnet resumed` 和 `iOS remote frame available` 日志判断连接与首帧是否恢复。使用 iCloud Passwords 和 1Password 分别验证 AutoFill。[iOS 真机步骤](ios-enhanced.md#真机验收步骤待执行) · [AutoFill 真机步骤](ios-password-autofill.md#device-validation--pending)
3. 用 iOS 和 Android 分别连接增强版及旧版 Windows。检查普通输入、只读和撤权；在负坐标、混合 DPI、旋转和跨屏场景检查原生多点触控、窗口恢复、坐标对齐、失焦回退与 PiP 裁切。在目标手机上用 `Mobile video AI` 日志核对实际增强帧率和耗时。

## 继续开发时的回归范围

- 共享页面优先检查 `home_page.dart`、`settings_page.dart`、`connection_page.dart` 与 `remote_page.dart` 的平台门控。`remote_page.dart` 同时管会话初始化、销毁、前后台、工具栏和画布，碰到输入或渲染问题应先沿对应功能模块定位。窗口专注会进 `input_model.dart` 和 `model.dart` 的坐标路径，改动后需同时验证专注中和普通桌面操作。[页面目录](../flutter/lib/mobile/pages/) · [输入模型](../flutter/lib/models/input_model.dart)
- 上游同步时需守住 Windows 会话原有权限、默认桌面和输入撤销逻辑。协议新增字段位于应用端 `libs/base/protos/message.proto`，`hbb_common` 与服务器共享。原生 bridge 文件由 CI 生成并忽略，新增接口按 `AGENTS.md` 手写相应 Dart 包装。Web 运行时独立于 Rust，维护者本地的 `flutter/web/js/src/` 未纳入本仓库，当前增强路径以原生客户端为范围。[连接](../src/server/connection.rs) · [输入服务](../src/server/input_service.rs) · [仓库开发规则](../AGENTS.md)
- 新增设置优先检查 `libs/base/src/config/keys.rs` 及已有 Dart 偏好存储，避免变更已保存的键名。新增文案按仓库规则追加到本地化词典。分发修改版时核对仓库许可证与打包生成的第三方声明，签名材料和用户配置留在部署环境。[配置键](../libs/base/src/config/keys.rs) · [本地化模板](../src/lang/template.rs) · [项目许可证](../LICENCE)
