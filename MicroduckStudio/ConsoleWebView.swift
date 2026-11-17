import SwiftUI
import WebKit

/// 用 WKWebView 直接加载机器人上的 Studio 页面（同源），不打包网页资源。
struct ConsoleWebView: UIViewRepresentable {
    let endpoint: RobotEndpoint
    let reloadToken: Int
    @Binding var loadError: String?
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.load(endpoint: endpoint, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != reloadToken
            || context.coordinator.lastEndpoint != endpoint {
            context.coordinator.load(endpoint: endpoint, in: webView)
        }
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: ConsoleWebView
        var lastReloadToken = -1
        var lastEndpoint: RobotEndpoint?

        init(_ parent: ConsoleWebView) {
            self.parent = parent
        }

        func load(endpoint: RobotEndpoint, in webView: WKWebView) {
            lastEndpoint = endpoint
            lastReloadToken = parent.reloadToken
            DispatchQueue.main.async {
                self.parent.loadError = nil
                self.parent.isLoading = true
            }
            let request = URLRequest(url: endpoint.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            webView.load(request)
        }

        private func allowed(_ endpoint: RobotEndpoint, scheme: String, host: String, port: Int) -> Bool {
            RobotAddress.matchesOrigin(endpoint: endpoint, scheme: scheme, host: host, port: port)
        }

        private func allowed(url: URL, endpoint: RobotEndpoint) -> Bool {
            guard let scheme = url.scheme, let host = url.host else { return false }
            let port = url.port ?? ((scheme.lowercased() == "https") ? 443 : 80)
            return allowed(endpoint, scheme: scheme, host: host, port: port)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url, let endpoint = lastEndpoint else {
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "about" || url.scheme == "blob" {
                decisionHandler(.allow)
                return
            }
            if allowed(url: url, endpoint: endpoint) {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = nil
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            present(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            present(error)
        }

        func webView(
            _ webView: WKWebView,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            // 默认走系统证书校验。不在这里接受自签证书，也不自动信任 /ca.crt。
            completionHandler(.performDefaultHandling, nil)
        }

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            guard let endpoint = lastEndpoint else {
                decisionHandler(.deny)
                return
            }
            // 只对当前填写的机器人源弹出系统权限询问，不对其它来源自动批准。
            if allowed(endpoint, scheme: origin.protocol, host: origin.host, port: Int(origin.port)) {
                decisionHandler(.prompt)
            } else {
                decisionHandler(.deny)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url, let endpoint = lastEndpoint, allowed(url: url, endpoint: endpoint) {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func present(_ error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                return
            }
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = self.message(for: error)
            }
        }

        private func message(for error: Error) -> String {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && (ns.code == NSURLErrorServerCertificateUntrusted
                || ns.code == NSURLErrorServerCertificateHasBadDate
                || ns.code == NSURLErrorServerCertificateHasUnknownRoot
                || ns.code == NSURLErrorServerCertificateNotYetValid
                || ns.code == NSURLErrorSecureConnectionFailed
                || ns.code == NSURLErrorClientCertificateRejected) {
                return "无法验证这台鸭子的 HTTPS 证书。若确认这是你的机器人，请按官方说明下载 CA，并在 iPhone「设置 → 通用 → 关于本机 → 证书信任设置」中打开信任。本应用不会自动信任自签证书。你也可以改用尚未启用 HTTPS 的 http 地址，或改用证书涵盖的主机名 / .local / 10.42.0.1。"
            }
            if ns.domain == NSURLErrorDomain && (ns.code == NSURLErrorCannotFindHost
                || ns.code == NSURLErrorDNSLookupFailed) {
                return "找不到这台主机。请确认手机和鸭子在同一网络，苹果设备优先尝试 duck-xxxx.local；若刚连上鸭子热点，请保持连接并必要时关掉移动数据。"
            }
            if ns.domain == NSURLErrorDomain && (ns.code == NSURLErrorTimedOut
                || ns.code == NSURLErrorCannotConnectToHost
                || ns.code == NSURLErrorNetworkConnectionLost
                || ns.code == NSURLErrorNotConnectedToInternet) {
                return "连不上控制台。请检查地址、端口 8000、网络权限，然后点「重试」。"
            }
            return "页面加载失败：\(error.localizedDescription)"
        }
    }
}
