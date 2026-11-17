import SwiftUI

struct ContentView: View {
    @State private var rawAddress: String = ""
    @State private var page: ConsolePage = .mobile
    @State private var endpoint: RobotEndpoint?
    @State private var formError: String?
    @State private var reloadToken = 0
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            if let endpoint {
                ConsoleScreen(
                    endpoint: endpoint,
                    reloadToken: $reloadToken,
                    loadError: $loadError,
                    isLoading: $isLoading,
                    onChangeAddress: { self.endpoint = nil },
                    onSwitchPage: { newPage in
                        self.page = newPage
                        var next = endpoint
                        next.page = newPage
                        RobotAddress.save(raw: rawAddress, page: newPage)
                        self.loadError = nil
                        self.endpoint = next
                        self.reloadToken += 1
                    }
                )
            } else {
                AddressFormView(
                    rawAddress: $rawAddress,
                    page: $page,
                    formError: $formError,
                    onOpen: open
                )
            }
        }
        .onAppear {
            if rawAddress.isEmpty, let saved = RobotAddress.loadSaved() {
                rawAddress = saved.raw
                page = saved.page
            }
        }
    }

    private func open() {
        formError = nil
        do {
            let parsed = try RobotAddress.parse(rawAddress, page: page)
            RobotAddress.save(raw: rawAddress, page: page)
            loadError = nil
            endpoint = parsed
            reloadToken += 1
        } catch {
            formError = (error as? LocalizedError)?.errorDescription ?? "地址无效。"
        }
    }
}

struct AddressFormView: View {
    @Binding var rawAddress: String
    @Binding var page: ConsolePage
    @Binding var formError: String?
    var onOpen: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("小鸭子控制台")
                    .font(.largeTitle.bold())
                Text("这是非官方的 iOS 外壳，用来在本机浏览器内核里打开机器人上的 Microduck Studio 网页。控制功能仍由鸭子上的服务提供；没有连上你的机器人时，不能当作已经可以遥控。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("机器人地址")
                    .font(.headline)
                TextField("例如 https://duck-xxxx.local:8000", text: $rawAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .submitLabel(.go)
                    .onSubmit(onOpen)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Picker("打开哪一页", selection: $page) {
                    ForEach(ConsolePage.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if let formError {
                    Text(formError)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }

                Button(action: onOpen) {
                    Text("打开控制台")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 8) {
                    Text("示例（请把 xxxx 换成你的鸭子名字，下面不是某台真实设备）")
                        .font(.headline)
                    ForEach(RobotAddress.examples, id: \.self) { example in
                        Text(example)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Text("家用 Wi-Fi 下的苹果设备通常用 duck-xxxx.local。鸭子自己的热点用 10.42.0.1。尚未启用 HTTPS 的旧镜像用 http。新镜像的 HTTPS 证书一般不含普通局域网 DHCP 地址，请优先用主机名或 .local，不要指望 https://192.168.x.x 能通过证书校验。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("地址只会保存在这台 iPhone 的本地设置里，不会上传，也不要把它写进公开仓库或截图发到公开地方。打开 HTTPS 站点时，本应用使用系统证书校验，不会自动信任鸭子的自签证书；如需麦克风等功能，请按官方说明安装并在系统设置中信任 Microduck Local CA。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConsoleScreen: View {
    let endpoint: RobotEndpoint
    @Binding var reloadToken: Int
    @Binding var loadError: String?
    @Binding var isLoading: Bool
    var onChangeAddress: () -> Void
    var onSwitchPage: (ConsolePage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ConsoleWebView(
                endpoint: endpoint,
                reloadToken: reloadToken,
                loadError: $loadError,
                isLoading: $isLoading
            )
            if let loadError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loadError)
                        .font(.footnote)
                    Button("重试") { reloadToken += 1 }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle(endpoint.origin)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("更改地址") { onChangeAddress() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if isLoading {
                        ProgressView()
                    }
                    Button("刷新") { reloadToken += 1 }
                    Menu("页面") {
                        Button("打开手机控制台") { onSwitchPage(.mobile) }
                        Button("打开桌面控制台") { onSwitchPage(.desktop) }
                    }
                }
            }
        }
    }
}
