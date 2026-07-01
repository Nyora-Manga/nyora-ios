//
//  UsernamePasswordTracker.swift
//  Aidoku
//
//  A protocol for trackers that authenticate with a username/email and password
//  (OAuth password grant) rather than a browser-based redirect flow.
//

import Foundation

protocol UsernamePasswordTracker: Tracker {
    /// Attempt to log in with the given credentials.
    ///
    /// - Returns: `true` if authentication succeeded.
    func login(username: String, password: String) async -> Bool
}
