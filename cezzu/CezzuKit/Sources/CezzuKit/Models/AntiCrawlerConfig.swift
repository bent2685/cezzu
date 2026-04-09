import Foundation

/// 反爬虫 / 验证码自动求解配置（cezzu-rule 格式 API ≥ 6 才支持）。
/// v1 仅做解码，运行时不消费 —— 把 captcha 流程留给后续 change。
public struct AntiCrawlerConfig: Codable, Hashable, Sendable {
    /// `1` = 图片验证码（用户输入）；`2` = 自动点击按钮（"我不是机器人"等）。
    public enum CaptchaType: Int, Codable, Sendable {
        case imageCaptcha = 1
        case autoClickButton = 2
    }

    public var enabled: Bool
    public var captchaType: CaptchaType
    public var captchaImage: String
    public var captchaInput: String
    public var captchaButton: String

    public init(
        enabled: Bool,
        captchaType: CaptchaType,
        captchaImage: String,
        captchaInput: String,
        captchaButton: String
    ) {
        self.enabled = enabled
        self.captchaType = captchaType
        self.captchaImage = captchaImage
        self.captchaInput = captchaInput
        self.captchaButton = captchaButton
    }
}
