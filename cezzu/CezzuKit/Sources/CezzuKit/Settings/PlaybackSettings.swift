import Foundation
import SwiftUI

/// 播放器相关的用户设置。
public enum PlaybackSettings {
    public static let enableLocalProxyKey = "cezzu.playback.enableLocalProxy"
    public static let enableDanmakuKey = "cezzu.playback.enableDanmaku"
    public static let danmakuFontSizeKey = "cezzu.playback.danmakuFontSize"
    public static let danmakuOpacityKey = "cezzu.playback.danmakuOpacity"
    public static let danmakuAreaKey = "cezzu.playback.danmakuArea"
    public static let danmakuDurationKey = "cezzu.playback.danmakuDuration"
    public static let danmakuLineHeightKey = "cezzu.playback.danmakuLineHeight"
    public static let showTopDanmakuKey = "cezzu.playback.showTopDanmaku"
    public static let showBottomDanmakuKey = "cezzu.playback.showBottomDanmaku"
    public static let showScrollDanmakuKey = "cezzu.playback.showScrollDanmaku"
    public static let followPlaybackRateDanmakuKey = "cezzu.playback.followPlaybackRateDanmaku"

    /// 默认值。
    public static let enableLocalProxyDefault = true
    public static let enableDanmakuDefault = true
    public static let danmakuFontSizeDefault = 22.0
    public static let danmakuOpacityDefault = 1.0
    public static let danmakuAreaDefault = 0.75
    public static let danmakuDurationDefault = 8.0
    public static let danmakuLineHeightDefault = 1.0
    public static let showTopDanmakuDefault = true
    public static let showBottomDanmakuDefault = true
    public static let showScrollDanmakuDefault = true
    public static let followPlaybackRateDanmakuDefault = true

    /// 当前值（同步读取）。
    public static var enableLocalProxy: Bool {
        get {
            if UserDefaults.standard.object(forKey: enableLocalProxyKey) == nil {
                return enableLocalProxyDefault
            }
            return UserDefaults.standard.bool(forKey: enableLocalProxyKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enableLocalProxyKey)
        }
    }

    public static var enableDanmaku: Bool {
        get {
            bool(forKey: enableDanmakuKey, defaultValue: enableDanmakuDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enableDanmakuKey)
        }
    }

    public static var danmakuFontSize: Double {
        get {
            double(forKey: danmakuFontSizeKey, defaultValue: danmakuFontSizeDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: danmakuFontSizeKey)
        }
    }

    public static var danmakuOpacity: Double {
        get {
            double(forKey: danmakuOpacityKey, defaultValue: danmakuOpacityDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: danmakuOpacityKey)
        }
    }

    public static var danmakuArea: Double {
        get {
            double(forKey: danmakuAreaKey, defaultValue: danmakuAreaDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: danmakuAreaKey)
        }
    }

    public static var danmakuDuration: Double {
        get {
            double(forKey: danmakuDurationKey, defaultValue: danmakuDurationDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: danmakuDurationKey)
        }
    }

    public static var danmakuLineHeight: Double {
        get {
            double(forKey: danmakuLineHeightKey, defaultValue: danmakuLineHeightDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: danmakuLineHeightKey)
        }
    }

    public static var showTopDanmaku: Bool {
        get {
            bool(forKey: showTopDanmakuKey, defaultValue: showTopDanmakuDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showTopDanmakuKey)
        }
    }

    public static var showBottomDanmaku: Bool {
        get {
            bool(forKey: showBottomDanmakuKey, defaultValue: showBottomDanmakuDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showBottomDanmakuKey)
        }
    }

    public static var showScrollDanmaku: Bool {
        get {
            bool(forKey: showScrollDanmakuKey, defaultValue: showScrollDanmakuDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showScrollDanmakuKey)
        }
    }

    public static var followPlaybackRateDanmaku: Bool {
        get {
            bool(forKey: followPlaybackRateDanmakuKey, defaultValue: followPlaybackRateDanmakuDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: followPlaybackRateDanmakuKey)
        }
    }

    private static func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func double(forKey key: String, defaultValue: Double) -> Double {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.double(forKey: key)
    }
}
