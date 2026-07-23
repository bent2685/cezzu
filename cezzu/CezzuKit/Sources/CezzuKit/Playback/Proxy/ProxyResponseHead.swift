import Foundation

/// 本地代理回给 AVPlayer 的 HTTP 响应头拼装。
///
/// 流式转发时 body 长度事先未知，此时不写 `Content-Length` —— 配合
/// `Connection: close` 就是合法的 close-delimited 分帧。
enum ProxyResponseHead {
    /// 只透传播放器真正需要的头，其余（Set-Cookie、CORS 之类）一律丢弃。
    static let passthrough = ["content-type", "content-range", "accept-ranges", "etag", "last-modified"]

    static func build(
        statusCode: Int,
        upstreamHeaders: [String: String],
        contentLength: Int?
    ) -> String {
        var head = "HTTP/1.1 \(statusCode) OK\r\n"
        for (key, value) in upstreamHeaders.sorted(by: { $0.key < $1.key })
        where passthrough.contains(key.lowercased()) {
            head += "\(key): \(value)\r\n"
        }
        if let contentLength {
            head += "Content-Length: \(contentLength)\r\n"
        }
        head += "Connection: close\r\n\r\n"
        return head
    }
}
