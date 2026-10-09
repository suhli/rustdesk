# RustDesk Enhanced for iOS

本实现基于 `1.5.0`（`fada664df`），保留 Flutter + Rust、hbbs/hbbr 协议和现有账号认证。增强代码主要位于 `flutter/lib/mobile/ios/`、`flutter/ios/IosEnhancements/`、`src/platform/ios_tailnet.rs` 和 `libs/ios_tailnet/`。没有提交私人服务器地址、账号 Token 或 Auth Key。

## 使用方式

在原有“设置 → ID/中继服务器”中填写自己的 ID Server、Relay Server、API Server 和 Server Key。没有自建服务器的用户仍可使用原有公共服务。

“设置 → 远程控制 → iOS 增强功能”包含以下选项：

- 地址簿首页、悬浮会话工具栏：默认开启，均可关闭。首页在窄窗口显示分段入口，在宽窗口显示侧栏；支持地址簿、收藏、最近连接、在线设备及原有可访问设备/发现入口。保留 ID 输入、搜索、刷新和原有设备操作；长按设备打开操作菜单。
- 远程会话方向：默认自动横屏，也可选择跟随系统、始终竖屏或手动旋转。iPad 默认不限制方向。工具栏中的旋转只影响当前会话。
- 内嵌 Tailscale：默认关闭。关闭时不启动 tsnet、不创建节点、不进行授权，也不建立 Tailscale 网络连接。
- 启动时自动连接：默认开启，仅在总开关开启且已授权时自动恢复。首次安装不会弹出 Tailnet 登录。
- Console API 使用 Tailscale：默认开启，但仅随总开关生效。ID、Relay 的 Tailscale 路由默认关闭，分别控制。

首次使用时先明确配置 API 地址，再打开内嵌 Tailscale。点击“授权”后会等待控制服务器生成授权链接（最多约 30 秒），并打开系统浏览器；等待期间显示进度，超时会提示检查控制服务器和网络。已有节点正在注册时不会因重复点击重启节点。如果系统或 LiveContainer 无法打开浏览器，可点击“复制授权链接”后手动在 Safari 打开。授权后手动返回应用即可恢复状态检查，不依赖自定义 URL 回调。若 Tailnet 启用了设备审批，还需在其管理控制台批准这个独立节点。

使用 Headscale 时，在“iOS 增强功能 → Tailscale / Headscale 控制服务器”填写其对外服务地址，例如 `https://headscale.example.com`；此地址用于节点注册，与 RustDesk 的 API/ID/中继服务器地址分别配置。留空使用官方 Tailscale。控制服务器必须在节点尚未连入 Tailnet 时就能从手机访问，HTTPS 使用系统信任的证书；也支持明确配置的 HTTP Headscale 地址。更改控制服务器的对话框会提示清除本应用当前节点身份，保存后需要重新授权，以免把原有身份用于另一个控制服务器。服务器端旧节点需自行管理。

Headscale 授权页面可能显示管理员注册命令，也可能跳转到部署者配置的 OIDC 登录；按该页面和当前 Headscale 版本完成注册，再返回应用。参见 [Headscale 注册说明](https://headscale.net/stable/ref/registration/)。当前没有增加 Auth Key 输入或跳过 TLS 验证。

节点由本应用在授权后加入所登录的 Tailnet，配置的主机名为 `rustdesk-ios`，无需手动填写节点 IP。旧版本在授权前可能显示 SDK 返回的系统主机名 `localhost`；这不是远端服务器地址，也不代表已经连接。现在授权前显示配置的节点名，获得网络信息后再显示实际节点名称和 Tailscale IP。

服务地址仍在“设置 → ID/中继服务器”里配置，填写对应服务器的 Tailscale IP 或 MagicDNS 名称和实际端口。API 地址需要带 `http://` 或 `https://`，例如 `http://100.101.102.103:21114`（示例地址，需替换）；不要填写本机的 `localhost`。仅 Console/API 位于 Tailnet 时，只开启“Console API 使用 Tailscale”；ID/中继也位于 Tailnet 时再开启各自的分流。首次授权使用“授权”，只有要丢弃现有身份、重新注册时才使用“授权新节点”。

已连接时显示节点名称、Tailscale IP，并自动进行一次 API 检查；也可手动重试。检查调用 `/api/login-options`，不带账号凭据。HTTP 4xx 表示服务器可达，不代表接口或账号认证成功；随后仍需通过原有账号登录、地址簿同步验证兼容性。

断开或禁用会关闭本机监听、在途转发和 tsnet，保留节点身份。更改分流开关会先断开；修改服务器地址后需重新连接。“授权新节点”和“清除本地身份”会经过明确提示，删除本地身份及其 Keychain 密钥；这不等于从 Tailscale 管理控制台删除设备。

## 内嵌网络实现和边界

选择官方 Go `tailscale.com/tsnet v1.96.5`，由 Go 1.26.5 编译成 ARM64 iOS 静态库，经 CocoaPods 链接。Swift MethodChannel 负责生命周期、Keychain 与状态，Rust 通过小型 C ABI 获取受限本机转发端口。没有修改 Flutter/Rust Bridge 的接口或协议。

社区 `tailscale 0.9.0` 的工具链要求高于本仓库 iOS 使用的 Flutter 3.24.5，因此没有为它升级整个 Flutter 工程。官方 tsnet 本身也不是经过本项目真机验收的现成 iOS 插件；此处的原生封装及静态链接必须通过下述 Xcode 构建验证。

请求路径：

1. 现有 Flutter `http_service.dart` 的匹配 API 请求强制进入现有 Rust HTTP bridge。
2. Rust `post_request_`、`get_http_response_async` 和严格 HTTP client 的薄钩子选择 iOS 网络模块，覆盖现有登录、OIDC 请求、账号刷新、地址簿以及使用这些入口的原生 API 请求。
3. Rust HTTP client 使用随机端口上的 `127.0.0.1` 代理。HTTP 只允许配置的 scheme/host/port；HTTPS 只允许对应 CONNECT 目标，TLS 仍由 Rust 校验证书，代理不解密 TLS。
4. ID、Relay 和在线状态查询使用独立 TCP 转发端口，目标固定；在线查询使用 ID 端口减一。Rust 原有帧封装、Server Key 校验、secure TCP / KeyExchange 保留在调用端。
5. Go 只使用 tsnet 的 netstack TCP 拨号，不使用可能退回系统网络的 `Server.Dial`。主机名仅在 Tailnet peer map 中解析，未知名称不发送给系统 DNS；IP 必须存在 Tailnet 路由。

普通 ID/Relay 服务默认仍走原有网络。只有配置匹配的 API origin 才改变 HTTP 路径；不会把更新检查等其他请求统统放进 Tailnet。配置变化导致旧转发器不匹配时明确失败，要求重新连接。

身份采用 SDK 的 `ipn.StateStore` 持久化：AES-256-GCM、随机 nonce、逻辑状态键作为认证附加数据、临时文件写入后原子替换。32 字节密钥保存在 `AfterFirstUnlockThisDeviceOnly` Keychain 条目中，状态目录排除设备备份。缺失密钥而仍有身份数据时拒绝覆盖。授权 URL 只在内存中使用；禁用 tsnet 日志上传和认证日志输出。

失败默认等待用户重连，不启用上游的公网 raw-TCP API 回落。用户可明确开启“使用已配置的备用服务器”，为 API、ID、Relay 分别填写备用地址；这些地址可能收到账号凭据。备用仅在本机转发器不存在或配置不匹配时使用，不自动重放已经发出的失败请求。网络中断后如需用备用地址，应先断开 Tailnet，再重试原操作。

资源策略：原生启动/停止/状态调用在串行后台队列上执行；Rust 查询端口不会等待慢速的状态调用。前台连接期间每 5 秒检查一次状态，已连接后每 30 秒一次；进入后台暂停轮询，无远程会话时停止已连接节点。正在远程控制时不主动关闭其网络，但不承诺 iOS 永久后台运行。

## 方向和触摸

`RemoteOrientationController` 排队处理进出会话方向请求，退出时恢复适用的首页策略。只在页面进入/退出或用户点击旋转时改变方向，不在重连、切换显示器或弹出键盘时反复旋转。

Flutter 先设置允许的方向，Swift 再从当前 Flutter 控制器所在的 `UIWindowScene` 请求方向变更。iOS 16+ 使用公开的 `requestGeometryUpdate`，较旧系统使用 `attemptRotationToDeviceOrientation`。请求后检查真实窗口方向，失败时给出重试/解除系统方向锁定提示。原有 Info.plist 已声明 iPhone 横竖屏和 iPad 四方向，无需重复修改。

没有实现“只旋转视频”的兜底，也没有修改鼠标、拖拽、滚动、缩放、外接键盘或触控板的坐标算法。若系统拒绝方向变更，会保持真实窗口与原有输入坐标的一致性。iOS 13–15 和系统方向锁定下的实际行为尚待真机验证；这不是已保证的无条件自动横屏。

悬浮工具栏提供退出、键盘、触摸/鼠标模式、显示和画质菜单、旋转、更多操作、手势帮助及隐藏按钮。空闲 6 秒自动收起，顶部保留可展开按钮；使用 SafeArea 和横向滚动适应窄屏。关闭增强工具栏后保留原来的工具栏路径。

## GitHub Actions

新入口是 `.github/workflows/ios-enhanced.yml` 的 `workflow_dispatch`。选择当前分支、独立 Bundle ID 和签名模式。工作流复用仓库现有的 bridge 生成工作流、Flutter 补丁及 vcpkg 构建步骤，固定 Flutter 3.24.5、Rust 1.75、Go 1.26.5、Xcode 16.4，使用 `macos-15` runner。

如果 Actions 页面没有工作流，先检查 Fork 是否已启用 Actions。手动运行的工作流文件必须先存在于仓库默认分支；仅推送到功能分支不会建立该手动入口。可以把增强分支设为此 Fork 的默认分支，或将工作流及其依赖合入默认分支，然后在 `iOS Enhanced → Run workflow` 中选择要构建的分支。参见 [GitHub 手动运行工作流说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)。

- `unsigned`：执行原生依赖、Go、Rust、Flutter 测试和 archive 构建，将归档中的 `Runner.app` 按 `Payload/Runner.app` 结构打包成 `RustDesk-Enhanced-unsigned.ipa`。在构建产物 `ios-enhanced-unsigned` 中解压找到 `.ipa`，可用于 LiveContainer 导入或后续重签名；不需要配置 Apple 签名 Secrets。它不能直接通过 iOS 的普通安装流程安装，LiveContainer 内的实际运行兼容性仍待真机验证。
- `development` / `ad-hoc` / `app-store`：导入证书、核验 profile 的 Team ID 和显式 Bundle ID、手动签名、导出 IPA、检查归档签名和 IPA 是否存在。签名材料在结束时清理。
- `app-store` 导出仅表示生成供上传的签名包；没有自动上传、App Store 审核或分发保证。上传要求可能需要更新 Xcode/SDK，需单独验证。

所有签名模式的最终 `ios-enhanced-*` artifact 只包含 IPA，不压缩上传 Xcode 归档或单独的许可证文件；许可证和第三方声明作为应用资源包含在 IPA 中。工作流依赖的 bridge artifact 仍用于各构建任务之间传递生成代码。

签名模式需配置仓库 Secrets：

- `APPLE_TEAM_ID`
- `IOS_CERTIFICATE_P12_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64`
- 可选 `IOS_BUNDLE_ID`，否则使用 dispatch 的 `bundle_id`。

Profile 必须与签名模式、证书及目标设备相符。Development/Ad Hoc 安装要求设备已包含在 profile 中。首次使用建议运行 unsigned；通过后再配置签名。工作流没有自动发布 release 或上传账号私密配置。

`scripts/ios_identity.py` 和 `scripts/ios_icon.swift` 在 CI 构建目录中设置独立 Bundle ID、RustDesk Enhanced 名称和原创几何图标。本地发布前也要运行它们；源仓库原始 iOS 资源保留，以减少上游合并冲突。脚本拒绝使用官方 `com.carriez.*` Bundle ID。

macOS 本地构建（先按仓库现有流程安装 vcpkg 依赖并生成 bridge）：

iOS 只生成 Rust 静态库，由 Xcode 将 `liblibrustdesk.a` 与 CocoaPods 提供的 Go 静态库 `libEmbeddedTailnet.a` 一起链接。使用下方的 `cargo rustc --crate-type staticlib`；普通 `cargo build --lib` 还会按共享 manifest 生成动态库，在 Go 库尚未参与链接时因缺少 `_rd_tailnet_port` 而失败。

```sh
bash libs/ios_tailnet/build-ios.sh
cargo rustc --locked --features flutter,hwcodec --release --target aarch64-apple-ios --lib --crate-type staticlib
export IOS_BUNDLE_ID=org.example.rustdesk.enhanced
python3 scripts/ios_identity.py
swift scripts/ios_icon.swift
cd flutter
flutter pub get
flutter test --no-pub test/ios_orientation_test.dart test/ios_tailnet_test.dart
flutter build ipa --release --no-codesign
```

首次进入 Xcode 前必须构建 Go 静态库，随后用 `flutter/ios/Runner.xcworkspace` 打开工程。签名可使用自己的 Xcode 配置，或工作流中的 profile/ExportOptions 流程。当前脚本只生成真机 ARM64 静态库，没有提供模拟器 slice。

## 验证状态

Windows 上已运行 Go 模块的身份恢复/篡改拒绝、代理目标白名单、响应和认证头保留、私有名称解析隔离、缺失 Tailnet 路由拒绝测试。Flutter 有 3 个方向策略测试，覆盖 iPhone 进入/退出、iPad/跟随系统、竖屏/手动模式。

Headscale 改动补充了无效控制地址拒绝的 Go 测试，以及延迟授权链接、浏览器打开失败后保留复制链接、控制地址校验的 Flutter 回归测试。Go 测试和 Dart 静态分析已通过；完整 Flutter 授权测试需要 CI 的 Flutter 3.24.5，本机 3.35.6 与项目既有 `extended_text` 依赖不兼容，未标记为通过。真实 Headscale 注册及 LiveContainer 浏览器跳转仍需安装新 IPA 验证。

静态分析仅覆盖本次新增模块及改动的 Dart 文件，不等同于整个 Flutter 应用或 iOS 原生构建。本机 Flutter 为 3.35.6/Dart 3.9.2；CI 保留上游 3.24.5，因此还需要 CI 验证。当前环境没有 Xcode 和 iPhone：Swift/Go iOS 链接、IPA 签名、真实 Tailnet 登录、第三方 Console 与 secure TCP 的端到端连接、真机旋转和触摸均未标记为通过。

### 真机验收步骤（待执行）

1. 先跑 unsigned CI，将产物中的 `RustDesk-Enhanced-unsigned.ipa` 导入已配置好的 LiveContainer 并验证启动。若使用普通安装流程，先配置签名，再使用 Xcode 的 Devices and Simulators 安装 Development/Ad Hoc IPA，或通过相应受支持的分发渠道安装。
2. 干净安装，保持 Tailnet 关闭：确认无额外授权/节点创建；测试官方或自建 ID/Relay、账号登录和远程控制。分别关闭首页和工具栏增强，确认原路径可用。
3. 配置自己的 API、ID、Relay、Server Key。仅开启 API 分流，浏览器授权后返回应用；测试第三方 Console 登录、地址簿拉取、设备连接和 Token 失效。ID/Relay 保持公网访问，检查 secure TCP / KeyExchange 仍能协商。
4. 断开内嵌节点，确认私有 API 报错且不会经公网 ID 代理发送；开启明确的备用地址后才允许使用备用。配置错误证书/Server Key 时必须失败。
5. 完全退出并重新打开应用，确认恢复同一节点身份；关闭自动连接后必须手动连接。禁用应停止节点但保留身份；清除身份后再授权应创建新身份，并按需从控制台删除旧设备。
6. 分别启用 ID 和 Relay 分流，用 Tailnet IP/MagicDNS 地址测试 TCP、在线状态和中继。ACL 拒绝、未批准节点、服务离线和错误地址应显示失败，不转用宿主机网络。
7. iPhone 开启/关闭系统方向锁定，测试进入会话横屏、退出恢复、连接失败返回、快速退出、重连、显示器切换和键盘输入。记录系统版本和实际方向；拒绝旋转时验证提示及手动按钮。
8. 分别验证触摸点击、右键、拖拽、滚轮、双指缩放、鼠标模式、工具栏收起/展开和退出。检查刘海、Dynamic Island、Home Indicator 与键盘遮挡。
9. iPad 测试横竖屏、窄窗口/宽窗口、多任务、外接键盘/鼠标/触控板；确认默认不套用 iPhone 的方向限制。
10. Wi-Fi/蜂窝切换、后台/前台切换、无会话后台停连及会话中后台行为；确认返回后可恢复，且没有无限高频重试。

## 已知限制

- ID 走 Tailnet 时按策略强制中继并禁用直连探测，不支持原生 UDP、P2P、WebRTC 经内嵌节点传输。Relay 的开关仍独立。服务器必须支持现有 TCP 信令/中继路径。
- 只解析 Tailnet peer map 中的 MagicDNS 全名或唯一短名，也支持有路由的 IP；没有接入任意公网 DNS、私有自定义 DNS 或通用出口节点模式。优先使用节点 IP/完整 MagicDNS 名称。`Sys().Dialer` 属于 tsnet 不稳定 API，升级 SDK 必须重新审查和测试隔离行为。
- ID/Relay 转发目标采用配置地址严格匹配；服务器下发其他中继别名时会拒绝。原有在线查询入口仅处理 `host:port`，IPv6 ID 地址的在线列表仍有上游限制；远控和 API 的 IPv6 需单独测试。
- 备用地址只用于新请求，不接管已建立的远程流或自动重发写请求。
- 在线分组查询当前地址簿的前 1000 个设备，每 20 秒一次，后台或远程会话中暂停；不是整个账号所有地址簿的全局在线聚合。
- API 暂时失败时保留当前已加载地址簿的显示，仍使用上游缓存/过期策略，没有新增永久离线账号数据存储。
- 内部画面旋转兜底、原生 iOS 模拟器库和真机验收尚未完成。方向请求不能绕过系统政策，后台存活也受 iOS 限制。

## 回归范围与上游同步

已修改的既有运行路径：

- `flutter/lib/mobile/pages/connection_page.dart`：仅 iOS 开启增强首页时挂载新首页；关闭后保留原滚动页面。
- `home_page.dart`：仅 iOS 初始化可选服务的配置观察器和首页方向；Tailnet 关闭时不调用节点启动。
- `remote_page.dart`：仅 iOS 调用方向控制和可选悬浮工具栏，旧画面、触摸和认证实现不变。
- `settings_page.dart`：仅 iOS 增加设置入口，受原有禁用设置开关约束。
- `flutter/lib/common/widgets/peer_card.dart`：仅 iOS 增强首页模式下长按打开原有菜单；其他模式保留原长按选择行为。
- `flutter/lib/utils/http_service.dart`：仅明确匹配的 iOS 私有 API 请求进入 Rust 分流，防止 Flutter 请求遗漏。
- `src/client.rs`：iOS 的 ID、Relay、在线查询 TCP 连接挂钩；ID 分流启用时设置会话中继策略并禁止 WebRTC 探测。关闭分流时调用原连接函数。
- `src/common.rs`：iOS 分流时拦截 API HTTP、禁止其公网 raw-TCP 回落，并跳过与私有 ID 不兼容的 NAT/服务器探测。其他分支保留原实现。
- `src/hbbs_http/account.rs`：匹配私有 API 时跳过旧 OIDC TLS 预热，避免先发系统网络请求；实际认证请求继续走原入口。
- `src/hbbs_http/http_client.rs`：严格 HTTP client 增加匹配私有 API 的入口，保持 TLS 验证。
- `src/platform/mod.rs`、`libs/base/src/config/keys.rs`：iOS 模块声明和新增独立配置键。
- `flutter/ios/Runner/AppDelegate.swift`、`flutter/ios/Podfile`：注册原生控制器、链接静态库；只有新 pod 设置 iOS 13 部署目标，其他 pod 保持原设置。
- `.github/workflows/flutter-build.yml`：原有 iOS 构建增加必需的 Go 静态库步骤；其他平台的 job 不变。
- `src/lang/*.rs`：仅追加新功能文案；简体中文提供翻译，其他语言回退英文，意大利语保持新增空值。`.gitignore` 仅忽略生成的 Go 二进制/头文件。

这些钩子用于覆盖实际的 Flutter/Rust 网络入口和 iOS 生命周期，不重构其他平台路径。没有改动或提升 `hbb_common` 子模块，也没有升级 Flutter pubspec 依赖。同步上游时优先检查这些薄钩子，特别是新增 HTTP 调用、secure TCP 调用位置和会话创建策略；若上游增加网络入口，应验证其是否需要同样的显式分流。

## 许可证与发布

保留根目录 `LICENCE`、版权声明和修改说明。RustDesk 使用 AGPL-3.0；分发修改版时应随版本提供相应源码和许可证，并按适用条款处理网络交互下的源码提供。`scripts/ios_licenses.py` 合并根目录 `LICENCE`、Go runtime 许可证以及实际链接的 Go 包的 Tailscale BSD-3-Clause 和传递依赖声明，生成 `THIRD-PARTY-NOTICES.txt`，通过 pod 资源包含在 IPA 中；缺失模块许可证时构建会失败，需审查后才能发布。没有复制 VoidLink 的代码、UI 素材或品牌资源。

参考：[官方 tsnet](https://tailscale.com/docs/features/tsnet)、[社区 Flutter SDK](https://pub.dev/packages/tailscale)、[UIKit 场景方向请求](https://developer.apple.com/documentation/uikit/uiwindowscene/requestgeometryupdate(_:errorhandler:))、[GitHub macOS 15 构建镜像](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)。
