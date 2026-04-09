import Foundation
import SwiftUI

/// 播放器相关的用户设置。当前 v1 只有一个开关：本地反代是否启用。
public enum PlaybackSettings {
    public static let enableLocalProxyKey = "cezzu.playback.enableLocalProxy"

    /// 默认值。
    public static let enableLocalProxyDefault = true

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
}
