# 小鸭子控制台（未签名 iOS 外壳）

这是 **viniedodo 自行维护的非官方 iOS 外壳**，用来在 iPhone / iPad 上打开机器人里的 [Microduck Studio](https://github.com/fanhao375/microduck-replica) 网页控制台。它 **不是** [fanhao375/microduck-replica](https://github.com/fanhao375/microduck-replica) 的官方应用，也不包含上游网页源码。

控制逻辑、登录、模型与运动指令都仍在鸭子上的 Studio 服务里。本仓库只提供一个 WKWebView 壳：你输入地址后，App 直接加载那个地址。没有连上你的机器人时，不能认为已经可以遥控。

## 系统要求

- iOS / iPadOS **16.0** 或更高。
- 与鸭子同一局域网，或连上鸭子自己的热点。
- 自行签名后安装。本仓库的 GitHub Actions 只生成 **未签名、真机 arm64** IPA，不含 Apple 证书或描述文件，不能直接装到未越狱的 iPhone。

## 对应的上游网页

- 上游仓库：https://github.com/fanhao375/microduck-replica
- 手机控制台路径：`/m`（`/m.html`）。这是 2026-11 起加入的页面，见提交 [feat: add mobile console for phones](https://github.com/fanhao375/microduck-replica/commit/1041ba23e14078d7ba1aca6a72facc9c6f785f53)。
- HTTPS 局部 CA 与离线说明：https://github.com/fanhao375/microduck-replica/blob/master/software/studio/deploy/OFFLINE.md
- 当前 GitHub 上标记为 Latest 的正式镜像仍可能是较旧的 **20261027**，那时还没有手机页和自动 HTTPS，请用 `http://duck-xxxx.local:8000/` 打开桌面控制台，或先确认板子已更新。
- 带手机页和自动 HTTPS 的能力出现在之后的开发分支，并在预发布镜像 [20261112 RC4](https://github.com/fanhao375/microduck-replica/releases/tag/microduck-replica-image-zero3w-20261112-rc4) 的校验文件中有记录。请以你板子上实际运行的 Studio 为准。

## 使用方法

1. 用你自己的工具为 `MicroduckStudio-unsigned.ipa` 签名并安装。
2. 打开「小鸭子控制台」，输入机器人地址。空地址时界面只给出占位示例（`duck-xxxx.local`、`10.42.0.1` 等），不是某台真实设备。
3. 选择「手机控制台（/m）」或「桌面控制台（/）」，点「打开控制台」。地址只保存在这台设备的本地设置中。
4. 进入页面后可用「刷新」「更改地址」，或切换手机 / 桌面页。加载失败时会出现原因和「重试」。

示例（把 `xxxx` 换成你的鸭子四位名）：

- 家用 Wi-Fi，已启用 HTTPS：`https://duck-xxxx.local:8000/m`
- 尚未启用 HTTPS 的旧镜像：`http://duck-xxxx.local:8000/m`
- 鸭子热点：`https://10.42.0.1:8000/m`（旧 HTTP 镜像则为 `http://10.42.0.1:8000/`）

不要在地址里填写账号密码。不要把真实设备地址或登录凭证提交到本仓库，也不要发到公开地方。

## HTTPS 与证书（请仔细阅读）

已启用 HTTPS 的 Studio 使用鸭子自己生成的局部 CA。本应用 **按系统默认规则校验证书**，**不会**自动下载或无条件信任 `/ca.crt`，也 **不会**接受任意自签证书。

若页面提示证书无法验证，且你确认这是自己的鸭子：

1. 用电脑或已能打开的浏览器，从该鸭子下载 CA（官方入口在手机页「更多 → 手机麦克风证书」，或 `https://<鸭子>:8000/ca.crt`）。只安装你自己从这台鸭子取得的证书。
2. iPhone：安装描述文件后，到 **设置 → 通用 → 关于本机 → 证书信任设置**，打开 `Microduck Local CA`。细节以官方 [离线说明](https://github.com/fanhao375/microduck-replica/blob/master/software/studio/deploy/OFFLINE.md) 为准。
3. 出厂证书的 SAN 通常只包含主机名、`*.local`、`localhost`、`10.42.0.1` 和 `127.0.0.1`，**不含**普通局域网 DHCP 地址。因此 `https://192.168.x.x:8000` 即使装了 CA 也可能失败，请优先用 `duck-xxxx.local`。

「手机说话」等需要麦克风的功能还依赖 HTTPS 安全上下文、系统已信任该 CA，以及你在系统弹窗中授权。本仓库 **没有在真机上验证** 麦克风、摄像头或完整遥控，不能承诺这些功能一定可用。

## 明文 HTTP

尚未启用 HTTPS 的旧镜像仍使用 `http://...:8000`。Info.plist 仅打开了 `NSAllowsLocalNetworking`，用于局域网和 `.local` 的明文访问，**不是**全局关闭 ATS，也不是允许任意公网 HTTP。请只在你自己的局域网里使用明文地址。

首次访问局域网或 `.local` 时，iOS 可能询问本地网络权限，请允许，否则页面无法打开。

## 构建未签名 IPA

公开仓库使用标准 GitHub-hosted `macos-latest` runner（按 GitHub 文档，公开库的标准托管 runner 不占用付费额度）。工作流不使用 secret，也不使用 larger runners。

构建步骤概要：对真机目的地 `generic/platform=iOS` 做 Release archive，并传入 `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`、空的 `CODE_SIGN_IDENTITY`；**不**调用需要签名身份的 `xcodebuild -exportArchive`。随后把 `.app` 放到 `Payload/` 里打成 zip/IPA，并检查 bundle id、可执行文件、arm64 真机 Mach-O、以及没有签名配置或描述文件。

在仓库根目录（macOS 且已安装 Xcode 时）也可本地执行同样步骤。Linux 开发机可先运行：

```bash
python3 scripts/test_robot_address.py
```

## 许可

本外壳以 MIT 许可发布，见 [LICENSE](LICENSE)。上游 Microduck Studio 仍遵循其自己的许可证；本仓库没有复制上游网页或固件文件。
