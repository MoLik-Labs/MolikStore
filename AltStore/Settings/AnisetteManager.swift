//
//  AnisetteManager.swift
//  SideStore
//
//  Created by Joseph Mattiello on 11/16/22.
//  Copyright © 2022 SideStore. All rights reserved.
//

import Foundation

public struct AnisetteManager {
    
    var menuURL: String {
        var url: String
        url = UserDefaults.standard.menuAnisetteURL
        return url
    }
    /// User defined URL from Settings/UserDefaults
    static var userURL: String? {
        var urlString: String?
        
        if UserDefaults.standard.textServer == false {
            urlString = UserDefaults.standard.textInputAnisetteURL
        }
        else {
            urlString = UserDefaults.standard.customAnisetteURL
        }
            
        
        // guard let urlString = UserDefaults.standard.customAnisetteURL, !urlString.isEmpty else { return nil }
        
        // Test it's a valid, usable URL. URL(string:) accepts relative/garbage strings
        // (e.g. "hello"), so also require an http(s) scheme and a host — otherwise a malformed
        // anisette URL would slip through and fail later at request time (a contributor to
        // "can't sign in / can't refresh" errors).
        if let urlString = urlString {
            guard let url = URL(string: urlString),
                  let scheme = url.scheme, ["http", "https"].contains(scheme),
                  url.host != nil, !urlString.trimmingCharacters(in: .whitespaces).isEmpty else {
                ELOG("UserDefaults has invalid `customAnisetteURL`: \(urlString)")
                return nil
            }
        }
        return urlString
    }
    static var defaultURL: String {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "ALTAnisetteURL") as? String else {
            assertionFailure("Info.plist has invalid `ALTAnisetteURL`")
            abort()
        }
        return url
    }
    static var currentURLString: String { userURL ?? defaultURL }
    // Force unwrap is safe here since we check validity before hand -- @JoeMatt
    
    /// User url or default from plist if none specified
    static var currentURL: URL { URL(string: currentURLString)! }
}
