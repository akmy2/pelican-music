import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit
import Combine

private struct SpotifyTokens: Codable {
    var access_token: String
    var refresh_token: String?
    var expires_in: Double
}

enum SecureStore {
    static func read() -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "PelicanMusic.Spotify", kSecAttrAccount as String: "tokens",
            kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    static func write(_ data: Data?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "PelicanMusic.Spotify", kSecAttrAccount as String: "tokens"]
        SecItemDelete(query as CFDictionary)
        guard let data else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw NSError(domain: "Keychain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Não foi possível guardar a conexão com segurança."])
        }
    }
}

@MainActor final class Spotify: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var connected = false
    @Published var busy = false
    @Published var message: String?
    @Published var clientID: String = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""
    private var tokens: SpotifyTokens?
    private var session: ASWebAuthenticationSession?
    private let redirect = "pelicanmusic://spotify-callback"

    override init() {
        super.init()
        if let data = SecureStore.read(), let saved = try? JSONDecoder().decode(SpotifyTokens.self, from: data) {
            tokens = saved; connected = true
        }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    func connect() {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { message = "Informe o Client ID do seu app no Spotify Developer Dashboard."; return }
        guard !busy else { return }
        if id != UserDefaults.standard.string(forKey: "spotifyClientID") { disconnect() }
        clientID = id
        UserDefaults.standard.set(id, forKey: "spotifyClientID")
        let verifier = UUID().uuidString + UUID().uuidString
        let state = UUID().uuidString
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
        url.queryItems = ["client_id": id, "response_type": "code", "redirect_uri": redirect,
            "code_challenge_method": "S256", "code_challenge": challenge, "state": state,
            "scope": "user-read-playback-state user-modify-playback-state"].map { URLQueryItem(name: $0.key, value: $0.value) }
        busy = true
        session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "pelicanmusic") { [weak self] callback, error in
            Task { @MainActor in
                guard let self else { return }
                defer { self.busy = false; self.session = nil }
                guard let callback else {
                    if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin { self.message = error?.localizedDescription ?? "Login não concluído." }
                    return
                }
                let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
                guard callback.host == "spotify-callback", items.first(where: { $0.name == "state" })?.value == state,
                      let code = items.first(where: { $0.name == "code" })?.value else {
                    self.message = "O Spotify não autorizou a conexão. Verifique o cadastro e o endereço de retorno."; return
                }
                do {
                    try await self.exchange(["grant_type": "authorization_code", "code": code,
                        "redirect_uri": self.redirect, "client_id": id, "code_verifier": verifier])
                    self.message = "Spotify conectado. Abra o Spotify e inicie uma música para ativar o dispositivo."
                } catch { self.message = error.localizedDescription }
            }
        }
        session?.presentationContextProvider = self
        if session?.start() != true { busy = false; message = "Não foi possível abrir o login."; session = nil }
    }
    func disconnect() {
        do { try SecureStore.write(nil); tokens = nil; connected = false }
        catch { message = error.localizedDescription }
    }
    private func exchange(_ fields: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        var next = try JSONDecoder().decode(SpotifyTokens.self, from: data)
        if next.refresh_token == nil { next.refresh_token = tokens?.refresh_token }
        try SecureStore.write(JSONEncoder().encode(next))
        tokens = next; connected = true
    }
    private func check(_ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let text: String
            switch status {
            case 401: text = "Conexão expirada. Conecte o Spotify novamente."
            case 403: text = "Spotify recusou o comando. Confira Premium, permissões e usuários autorizados no Dashboard."
            case 404: text = "Nenhum dispositivo ativo. Abra o Spotify no iPhone e toque uma música primeiro."
            case 429: text = "Limite de pedidos do Spotify atingido. Aguarde antes de tentar novamente."
            default: text = "Spotify retornou erro \(status). Confira a configuração e tente novamente."
            }
            throw NSError(domain: "Spotify", code: status, userInfo: [NSLocalizedDescriptionKey: text])
        }
    }
    func command(_ action: String, link: String = "") async {
        guard connected, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            // Refresh before each user command; no background polling or stored client secret.
            guard let refresh = tokens?.refresh_token else { disconnect(); message = "Conecte o Spotify novamente."; return }
            try await exchange(["grant_type": "refresh_token", "refresh_token": refresh,
                "client_id": UserDefaults.standard.string(forKey: "spotifyClientID") ?? clientID])
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/\(action)")!)
            request.httpMethod = ["next", "previous"].contains(action) ? "POST" : "PUT"
            request.setValue("Bearer \(tokens!.access_token)", forHTTPHeaderField: "Authorization")
            if action == "play", !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let uri = try spotifyURI(link)
                let body: [String: Any] = uri.hasPrefix("spotify:track:") ? ["uris": [uri]] : ["context_uri": uri]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (_, response) = try await URLSession.shared.data(for: request)
            try check(response)
            message = "Comando enviado ao Spotify."
        } catch { message = error.localizedDescription }
    }
    private func spotifyURI(_ text: String) throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = text.split(separator: ":").map(String.init)
        if let url = URL(string: text), url.scheme == "https", url.host == "open.spotify.com" {
            let path = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
            if path.count == 2 { parts = ["spotify", path[0], path[1]] }
        }
        guard parts.count == 3, parts[0] == "spotify", ["track", "album", "playlist"].contains(parts[1]),
              !parts[2].isEmpty, parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw NSError(domain: "Spotify", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cole um link de música, álbum ou playlist do Spotify."])
        }
        return parts.joined(separator: ":")
    }
}
