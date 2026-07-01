//
//  KitsuApi.swift
//  Aidoku
//
//  REST (JSON:API) client for the Kitsu tracker.
//

import Foundation

actor KitsuApi {
    static let baseUrl = "https://kitsu.app"
    static let apiUrl = "https://kitsu.app/api/edge"
    static let vndJson = "application/vnd.api+json"

    private let decoder = JSONDecoder()

    private static let tokenKey = "Tracker.kitsu.token"
    private static let refreshKey = "Tracker.kitsu.refresh"
    private static let userIdKey = "Tracker.kitsu.userId"

    nonisolated var accessToken: String? {
        UserDefaults.standard.string(forKey: Self.tokenKey)
    }

    nonisolated var refreshToken: String? {
        UserDefaults.standard.string(forKey: Self.refreshKey)
    }

    private func setTokens(access: String?, refresh: String?) {
        let defaults = UserDefaults.standard
        if let access {
            defaults.set(access, forKey: Self.tokenKey)
        } else {
            defaults.removeObject(forKey: Self.tokenKey)
        }
        if let refresh {
            defaults.set(refresh, forKey: Self.refreshKey)
        }
    }

    func logout() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.tokenKey)
        defaults.removeObject(forKey: Self.refreshKey)
        defaults.removeObject(forKey: Self.userIdKey)
    }
}

// MARK: - Authentication
extension KitsuApi {
    func authenticate(username: String, password: String) async -> Bool {
        guard let url = URL(string: "\(Self.baseUrl)/api/oauth/token") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "grant_type": "password",
            "username": username,
            "password": password
        ].percentEncoded()

        guard
            let response: OAuthResponse = try? await URLSession.shared.object(from: request),
            let token = response.accessToken
        else {
            return false
        }
        setTokens(access: token, refresh: response.refreshToken)
        _ = await getCurrentUserId()
        return true
    }

    func refreshAccessToken() async -> Bool {
        guard
            let refresh = refreshToken,
            let url = URL(string: "\(Self.baseUrl)/api/oauth/token")
        else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "grant_type": "refresh_token",
            "refresh_token": refresh
        ].percentEncoded()

        guard
            let response: OAuthResponse = try? await URLSession.shared.object(from: request),
            let token = response.accessToken
        else {
            return false
        }
        setTokens(access: token, refresh: response.refreshToken ?? refresh)
        return true
    }
}

// MARK: - Requests
private extension KitsuApi {
    func authorizedRequest(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.vndJson, forHTTPHeaderField: "Accept")
        request.setValue(Self.vndJson, forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
        }
        return request
    }

    @discardableResult
    func requestData(_ request: URLRequest) async throws -> Data {
        var (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode

        if statusCode == 401, refreshToken != nil {
            if await refreshAccessToken() {
                var retry = request
                if let token = accessToken {
                    retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                (data, _) = try await URLSession.shared.data(for: retry)
            }
        }

        return data
    }
}

// MARK: - Data
extension KitsuApi {
    func getCurrentUserId() async -> String? {
        if let cached = UserDefaults.standard.string(forKey: Self.userIdKey) {
            return cached
        }
        guard
            let url = URL(string: "\(Self.apiUrl)/users?filter[self]=true"),
            let data = try? await requestData(authorizedRequest(url: url)),
            let response = try? decoder.decode(KitsuDataResponse<[KitsuResource<KitsuUserAttributes>]>.self, from: data),
            let id = response.data.first?.id
        else {
            return nil
        }
        UserDefaults.standard.set(id, forKey: Self.userIdKey)
        return id
    }

    func search(query: String) async -> [KitsuResource<KitsuMangaAttributes>] {
        guard var components = URLComponents(string: "\(Self.apiUrl)/manga") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "page[limit]", value: "20"),
            URLQueryItem(name: "filter[text]", value: query)
        ]
        guard
            let url = components.url,
            let data = try? await requestData(authorizedRequest(url: url)),
            let response = try? decoder.decode(KitsuDataResponse<[KitsuResource<KitsuMangaAttributes>]>.self, from: data)
        else {
            return []
        }
        return response.data
    }

    func getManga(id: String) async -> KitsuResource<KitsuMangaAttributes>? {
        guard
            let url = URL(string: "\(Self.apiUrl)/manga/\(id)"),
            let data = try? await requestData(authorizedRequest(url: url)),
            let response = try? decoder.decode(KitsuDataResponse<KitsuResource<KitsuMangaAttributes>>.self, from: data)
        else {
            return nil
        }
        return response.data
    }

    func findLibraryEntry(mangaId: String) async -> KitsuResource<KitsuLibraryAttributes>? {
        guard let userId = await getCurrentUserId() else { return nil }
        guard var components = URLComponents(string: "\(Self.apiUrl)/library-entries") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "filter[manga_id]", value: mangaId),
            URLQueryItem(name: "filter[userId]", value: userId),
            URLQueryItem(name: "filter[kind]", value: "manga")
        ]
        guard
            let url = components.url,
            let data = try? await requestData(authorizedRequest(url: url)),
            let response = try? decoder.decode(KitsuDataResponse<[KitsuResource<KitsuLibraryAttributes>]>.self, from: data)
        else {
            return nil
        }
        return response.data.first
    }

    @discardableResult
    func createLibraryEntry(mangaId: String, status: String, progress: Int) async -> String? {
        guard let userId = await getCurrentUserId() else { return nil }
        let payload: [String: Any] = [
            "data": [
                "type": "libraryEntries",
                "attributes": [
                    "status": status,
                    "progress": progress
                ],
                "relationships": [
                    "manga": ["data": ["type": "manga", "id": mangaId]],
                    "user": ["data": ["type": "users", "id": userId]]
                ]
            ]
        ]
        guard
            let body = try? JSONSerialization.data(withJSONObject: payload),
            let url = URL(string: "\(Self.apiUrl)/library-entries"),
            let data = try? await requestData(authorizedRequest(url: url, method: "POST", body: body)),
            let response = try? decoder.decode(KitsuDataResponse<KitsuResource<KitsuLibraryAttributes>>.self, from: data)
        else {
            return nil
        }
        return response.data.id
    }

    func updateLibraryEntry(entryId: String, attributes: [String: Any]) async {
        let payload: [String: Any] = [
            "data": [
                "type": "libraryEntries",
                "id": entryId,
                "attributes": attributes
            ]
        ]
        guard
            let body = try? JSONSerialization.data(withJSONObject: payload),
            let url = URL(string: "\(Self.apiUrl)/library-entries/\(entryId)")
        else {
            return
        }
        _ = try? await requestData(authorizedRequest(url: url, method: "PATCH", body: body))
    }
}
