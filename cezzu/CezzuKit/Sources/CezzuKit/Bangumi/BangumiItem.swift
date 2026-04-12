import Foundation

/// Bangumi.tv 番剧条目（subject type=2）。
///
/// 这是 Cezzu 主页 / 元数据详情页用的核心模型。
/// 数据来自 https://api.bgm.tv/v0/search/subjects （旧 API）
/// 与 https://next.bgm.tv/p1/trending/subjects（新 API）。
/// 两个 API 返回的字段大同小异，但有几处差异由本类型的自定义 Codable 处理：
///   - `name_cn` 在新 API 里也叫 `nameCN`；缺失时回落到 `name`
///   - `rating.score` / `rating.rank` 在某些条目里可能为 `null`
///   - `images` 在不存在时回落到顶层 `image`（旧字段）
public struct BangumiItem: Hashable, Sendable, Identifiable, Codable {
    public let id: Int
    public let name: String
    public let nameCn: String
    public let summary: String
    public let airDate: String
    public let rank: Int
    public let ratingScore: Double
    public let ratingTotal: Int
    public let eps: Int
    public let platform: String
    public let episodeDuration: String
    public let images: BangumiImages
    public let tags: [BangumiTag]

    public init(
        id: Int,
        name: String,
        nameCn: String,
        summary: String,
        airDate: String,
        rank: Int,
        ratingScore: Double,
        images: BangumiImages,
        tags: [BangumiTag],
        ratingTotal: Int = 0,
        eps: Int = 0,
        platform: String = "",
        episodeDuration: String = ""
    ) {
        self.id = id
        self.name = name
        self.nameCn = nameCn
        self.summary = summary
        self.airDate = airDate
        self.rank = rank
        self.ratingScore = ratingScore
        self.ratingTotal = ratingTotal
        self.eps = eps
        self.platform = platform
        self.episodeDuration = episodeDuration
        self.images = images
        self.tags = tags
    }

    /// 显示名 —— 优先中文名，没有就用日文名。
    public var displayName: String {
        nameCn.isEmpty ? name : nameCn
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameCn = "name_cn"
        case nameCNCamel = "nameCN"     // next.bgm.tv 偶尔用驼峰
        case summary
        case date
        case airDate
        case images
        case image                       // 旧 API 顶层 image 字段
        case rating
        case tags
        case eps
        case platform
        case infobox
    }

    private enum RatingKeys: String, CodingKey {
        case rank
        case score
        case total
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""

        // name_cn 优先 snake，再 camel，最后回落到 name
        let snakeCn = (try? c.decode(String.self, forKey: .nameCn)) ?? ""
        let camelCn = (try? c.decode(String.self, forKey: .nameCNCamel)) ?? ""
        let chosenCn = !snakeCn.isEmpty ? snakeCn : camelCn
        self.nameCn = chosenCn.isEmpty ? self.name : chosenCn

        self.summary = (try? c.decode(String.self, forKey: .summary)) ?? ""

        // 旧 API 用 `date`，新 API 也用 `date`，但有些种子用 `airDate`
        let snakeDate = (try? c.decode(String.self, forKey: .date)) ?? ""
        let camelDate = (try? c.decode(String.self, forKey: .airDate)) ?? ""
        self.airDate = !snakeDate.isEmpty ? snakeDate : camelDate

        // images：优先嵌套 dict，没有就把顶层 image 字段塞进 large
        if let nested = try? c.decode(BangumiImages.self, forKey: .images) {
            self.images = nested
        } else if let flat = try? c.decode(String.self, forKey: .image) {
            self.images = BangumiImages(large: flat, common: flat, medium: flat, small: flat, grid: flat)
        } else {
            self.images = BangumiImages.empty
        }

        // rating 子树
        if let rc = try? c.nestedContainer(keyedBy: RatingKeys.self, forKey: .rating) {
            self.rank = (try? rc.decode(Int.self, forKey: .rank)) ?? 0
            self.ratingScore = (try? rc.decode(Double.self, forKey: .score)) ?? 0.0
            self.ratingTotal = (try? rc.decode(Int.self, forKey: .total)) ?? 0
        } else {
            self.rank = 0
            self.ratingScore = 0.0
            self.ratingTotal = 0
        }

        // tags：缺失时空数组
        self.tags = (try? c.decode([BangumiTag].self, forKey: .tags)) ?? []

        // eps / platform：仅完整 subject 接口返回
        self.eps = (try? c.decode(Int.self, forKey: .eps)) ?? 0
        self.platform = (try? c.decode(String.self, forKey: .platform)) ?? ""

        // infobox → 提取片长（剧场版用 "片长"，TV 可能用 "每集时长"）
        if let entries = try? c.decode([InfoboxEntry].self, forKey: .infobox) {
            self.episodeDuration = entries.first(where: {
                $0.key == "片长" || $0.key == "每集时长" || $0.key == "时长"
            })?.stringValue ?? ""
        } else {
            self.episodeDuration = ""
        }
    }

    public func encode(to encoder: any Encoder) throws {
        // 写入用规范 snake_case，方便缓存 / 调试。
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(nameCn, forKey: .nameCn)
        try c.encode(summary, forKey: .summary)
        try c.encode(airDate, forKey: .date)
        try c.encode(images, forKey: .images)
        try c.encode(tags, forKey: .tags)
        try c.encode(eps, forKey: .eps)
        try c.encode(platform, forKey: .platform)
        var rc = c.nestedContainer(keyedBy: RatingKeys.self, forKey: .rating)
        try rc.encode(rank, forKey: .rank)
        try rc.encode(ratingScore, forKey: .score)
        try rc.encode(ratingTotal, forKey: .total)
    }
}

// MARK: - Infobox decoding (private)

/// Bangumi `/v0/subjects/{id}` 返回的 infobox 条目。
/// `value` 可以是纯字符串，也可以是 `[{"k": "...", "v": "..."}]` 数组。
private struct InfoboxEntry: Decodable {
    let key: String
    let value: Value

    enum Value: Decodable {
        case string(String)
        case array([Item])

        struct Item: Decodable {
            let v: String
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self) {
                self = .string(str)
            } else if let items = try? container.decode([Item].self) {
                self = .array(items)
            } else {
                self = .string("")
            }
        }
    }

    var stringValue: String {
        switch value {
        case .string(let s): return s
        case .array(let items): return items.map(\.v).joined(separator: "、")
        }
    }
}
