//
//  AIEndpointPolicyTests.swift
//  AidokuTests
//

import Foundation
import Testing
@testable import Aidoku

@Suite("AI endpoint policy")
struct AIEndpointPolicyTests {
    @Test("Normalizes an OpenAI-compatible HTTPS base URL")
    func normalizesHTTPSBaseURL() {
        let url = AIEndpointPolicy.chatCompletionsURL(baseURL: " https://api.example.com/v1/ ")

        #expect(url?.absoluteString == "https://api.example.com/v1/chat/completions")
    }

    @Test("Does not duplicate an existing chat-completions path")
    func preservesChatCompletionsPath() {
        let url = AIEndpointPolicy.chatCompletionsURL(
            baseURL: "https://api.example.com/v1/chat/completions?unexpected=value#fragment"
        )

        #expect(url?.absoluteString == "https://api.example.com/v1/chat/completions")
    }

    @Test("Does not collapse case-sensitive provider paths in cache identities")
    func preservesPathCaseInCacheIdentity() {
        let upper = AIEndpointPolicy.cacheIdentity(for: "https://api.example.com/Provider/V1")
        let lower = AIEndpointPolicy.cacheIdentity(for: "https://api.example.com/provider/v1")

        #expect(upper != lower)
    }

    @Test("Rejects unsafe remote HTTP and URL credentials")
    func rejectsUnsafeEndpoints() {
        #expect(AIEndpointPolicy.chatCompletionsURL(baseURL: "http://api.example.com/v1") == nil)
        #expect(AIEndpointPolicy.chatCompletionsURL(baseURL: "https://secret@example.com/v1") == nil)
        #expect(AIEndpointPolicy.chatCompletionsURL(baseURL: "ftp://api.example.com/v1") == nil)
    }

    @Test("Allows only explicit loopback HTTP development endpoints")
    func permitsLoopbackHTTPOnly() {
        #expect(
            AIEndpointPolicy.chatCompletionsURL(baseURL: "http://localhost:11434/v1")?.absoluteString
                == "http://localhost:11434/v1/chat/completions"
        )
        #expect(
            AIEndpointPolicy.chatCompletionsURL(baseURL: "http://127.0.0.1:1234/v1")?.absoluteString
                == "http://127.0.0.1:1234/v1/chat/completions"
        )
        #expect(
            AIEndpointPolicy.chatCompletionsURL(baseURL: "http://[::1]:8080/v1")?.absoluteString
                == "http://[::1]:8080/v1/chat/completions"
        )
    }

    @Test("Rejects cross-origin and insecure redirects")
    func redirectOriginRules() throws {
        let origin = try #require(URL(string: "https://api.example.com/v1/chat/completions"))
        let sameOrigin = try #require(URL(string: "https://api.example.com/another-path"))
        let crossOrigin = try #require(URL(string: "https://other.example.com/v1/chat/completions"))
        let downgraded = try #require(URL(string: "http://api.example.com/v1/chat/completions"))

        #expect(AIEndpointPolicy.sameOrigin(origin, sameOrigin))
        #expect(!AIEndpointPolicy.sameOrigin(origin, crossOrigin))
        #expect(!AIEndpointPolicy.sameOrigin(origin, downgraded))
    }

    @Test("Bounds BYOK response buffering")
    func boundsBYOKResponseBuffering() {
        #expect(AIEndpointPolicy.maximumBYOKResponseBytes == 4 * 1_024 * 1_024)
    }
}
