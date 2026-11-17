import Foundation

@main
struct RobotAddressTests {
    static func main() throws {
        var args = CommandLine.arguments
        args.removeFirst()
        guard let path = args.first else {
            fputs("usage: robot-address-tests <address_fixtures.json>\n", stderr)
            exit(2)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: data)
        var failed = 0

        for c in fixtures.accept {
            let page = page(c.page)
            do {
                let got = try RobotAddress.parse(c.raw, page: page)
                if got.scheme != c.scheme || got.host != c.host || got.port != c.port || got.displayURL != c.url {
                    failed += 1
                    fputs("FAIL accept \(c.raw): got \(got.scheme) \(got.host) \(got.port) \(got.displayURL) want \(c.scheme) \(c.host) \(c.port) \(c.url)\n", stderr)
                } else {
                    print("OK   accept \(c.raw) -> \(got.displayURL)")
                }
            } catch {
                failed += 1
                fputs("FAIL accept \(c.raw): raised \(error)\n", stderr)
            }
        }

        for c in fixtures.reject {
            let page = page(c.page)
            do {
                let got = try RobotAddress.parse(c.raw, page: page)
                failed += 1
                fputs("FAIL reject \(c.raw): unexpectedly accepted as \(got.displayURL)\n", stderr)
            } catch let err as RobotAddressError {
                if code(err) != c.error {
                    failed += 1
                    fputs("FAIL reject \(c.raw): got \(code(err)) want \(c.error)\n", stderr)
                } else {
                    print("OK   reject \(c.raw) (\(c.error))")
                }
            } catch {
                failed += 1
                fputs("FAIL reject \(c.raw): unexpected \(error)\n", stderr)
            }
        }

        if failed > 0 {
            fputs("\n\(failed) failure(s)\n", stderr)
            exit(1)
        }
        print("\nAll Swift address fixture tests passed.")
    }

    static func page(_ raw: String) -> ConsolePage {
        ConsolePage(rawValue: raw) ?? {
            fputs("unknown page \(raw)\n", stderr)
            exit(2)
        }()
    }

    static func code(_ err: RobotAddressError) -> String {
        switch err {
        case .empty: return "empty"
        case .invalidScheme: return "invalidScheme"
        case .credentialsForbidden: return "credentialsForbidden"
        case .missingHost: return "missingHost"
        case .invalidHost: return "invalidHost"
        case .invalidPort: return "invalidPort"
        case .invalidURL: return "invalidURL"
        }
    }
}

struct Fixtures: Codable {
    var accept: [Accept]
    var reject: [Reject]
    struct Accept: Codable {
        var raw: String
        var page: String
        var scheme: String
        var host: String
        var port: Int
        var url: String
    }
    struct Reject: Codable {
        var raw: String
        var page: String
        var error: String
    }
}
