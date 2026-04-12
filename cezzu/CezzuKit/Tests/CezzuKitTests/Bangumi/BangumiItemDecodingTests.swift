import Foundation
import Testing
@testable import CezzuKit

@Suite("BangumiItem decoding")
struct BangumiItemDecodingTests {

    /// next.bgm.tv `/p1/trending/subjects` 返回的形态（嵌套在 `subject` 之下）。
    /// 这里只 decode `subject` 内层。
    @Test("trending: nested subject decodes")
    func decodeTrendingSubject() throws {
        let json = """
        {
            "id": 467461,
            "type": 2,
            "name": "葬送のフリーレン",
            "name_cn": "葬送的芙莉莲",
            "summary": "魔王讨伐之旅结束后的故事。",
            "date": "2023-09-29",
            "images": {
                "large": "https://lain.bgm.tv/r/large/467461.jpg",
                "common": "https://lain.bgm.tv/r/common/467461.jpg",
                "medium": "https://lain.bgm.tv/r/medium/467461.jpg",
                "small": "https://lain.bgm.tv/r/small/467461.jpg",
                "grid": "https://lain.bgm.tv/r/grid/467461.jpg"
            },
            "rating": {
                "rank": 5,
                "score": 9.1
            },
            "tags": [
                {"name": "奇幻", "count": 1000},
                {"name": "治愈", "count": 800}
            ]
        }
        """
        let item = try JSONDecoder().decode(BangumiItem.self, from: Data(json.utf8))
        #expect(item.id == 467461)
        #expect(item.name == "葬送のフリーレン")
        #expect(item.nameCn == "葬送的芙莉莲")
        #expect(item.airDate == "2023-09-29")
        #expect(item.rank == 5)
        #expect(item.ratingScore == 9.1)
        #expect(item.images.large == "https://lain.bgm.tv/r/large/467461.jpg")
        #expect(item.tags.count == 2)
        #expect(item.tags[0].name == "奇幻")
        #expect(item.tags[0].count == 1000)
        #expect(item.displayName == "葬送的芙莉莲")
    }

    /// api.bgm.tv `/v0/search/subjects` 返回的旧形态。`name_cn` 必填但可能为空串。
    @Test("search: api.bgm.tv subject decodes")
    func decodeApiSubject() throws {
        let json = """
        {
            "id": 12345,
            "name": "Some Anime",
            "name_cn": "",
            "summary": "test",
            "date": "2024-01-01",
            "images": {
                "large": "https://example.com/large.jpg",
                "common": "https://example.com/common.jpg",
                "medium": "https://example.com/medium.jpg",
                "small": "https://example.com/small.jpg",
                "grid": "https://example.com/grid.jpg"
            },
            "rating": {
                "rank": 100,
                "score": 7.5
            },
            "tags": []
        }
        """
        let item = try JSONDecoder().decode(BangumiItem.self, from: Data(json.utf8))
        #expect(item.id == 12345)
        #expect(item.name == "Some Anime")
        // name_cn 是空串 → displayName 回落到日文名
        #expect(item.nameCn == "Some Anime")
        #expect(item.displayName == "Some Anime")
        #expect(item.tags.isEmpty)
    }

    /// next.bgm.tv 偶尔用驼峰 `nameCN` 而不是下划线 `name_cn`。
    @Test("camelCase nameCN is accepted")
    func decodeCamelNameCN() throws {
        let json = """
        {
            "id": 1,
            "name": "JP Title",
            "nameCN": "中文标题",
            "images": {"large": "u", "common": "u", "medium": "u", "small": "u", "grid": "u"},
            "rating": {"rank": 0, "score": 0}
        }
        """
        let item = try JSONDecoder().decode(BangumiItem.self, from: Data(json.utf8))
        #expect(item.nameCn == "中文标题")
        #expect(item.displayName == "中文标题")
    }

    /// 极端情况：rating 完全缺失 / images 缺失，不能 crash。
    @Test("missing rating and images defaults gracefully")
    func decodeMissingFields() throws {
        let json = """
        {
            "id": 999,
            "name": "Bare Bones",
            "name_cn": "光板"
        }
        """
        let item = try JSONDecoder().decode(BangumiItem.self, from: Data(json.utf8))
        #expect(item.id == 999)
        #expect(item.nameCn == "光板")
        #expect(item.rank == 0)
        #expect(item.ratingScore == 0.0)
        #expect(item.images.large == "")
        #expect(item.images.best == "")
        #expect(item.tags.isEmpty)
    }

    /// 旧 API 顶层 `image` 字段（不是嵌套 `images.large`）。
    @Test("legacy top-level image field falls back into images.large")
    func decodeLegacyImageField() throws {
        let json = """
        {
            "id": 42,
            "name": "Legacy",
            "name_cn": "旧版",
            "image": "https://legacy.example.com/cover.jpg",
            "rating": {"rank": 0, "score": 0}
        }
        """
        let item = try JSONDecoder().decode(BangumiItem.self, from: Data(json.utf8))
        #expect(item.images.large == "https://legacy.example.com/cover.jpg")
        #expect(item.images.best == "https://legacy.example.com/cover.jpg")
    }

    /// `images.best` 应该跳过空串挑第一个非空。
    @Test("BangumiImages.best skips empty strings")
    func bestImagePrefersNonEmpty() {
        let images = BangumiImages(large: "", common: "", medium: "m", small: "", grid: "")
        #expect(images.best == "m")
    }

    @Test("BangumiImages.empty has all empty strings")
    func emptyImagesIsEmpty() {
        #expect(BangumiImages.empty.large.isEmpty)
        #expect(BangumiImages.empty.best.isEmpty)
    }

    /// 完整 subject 接口返回的 eps / platform / rating.total / infobox 能正确解码。
    @Test("full subject: eps, platform, ratingTotal, and infobox duration decode")
    func decodeFullSubjectFields() throws {
        let json = """
        {
            "id": 467461,
            "name": "ダンダダン",
            "name_cn": "胆大党",
            "summary": "",
            "date": "2024-10-03",
            "eps": 12,
            "platform": "TV",
            "images": {"large": "L", "common": "C", "medium": "M", "small": "S", "grid": "G"},
            "rating": {"rank": 954, "score": 7.5, "total": 15667},
            "tags": [],
            "infobox": [
                {"key": "中文名", "value": "胆大党"},
                {"key": "话数", "value": "12"},
                {"key": "放送开始", "value": "2024年10月3日"},
                {"key": "放送星期", "value": "星期四"},
                {"key": "别名", "value": [{"v": "当哒当"}, {"v": "DAN DA DAN"}]}
            ]
        }
        """
        let item = try JSONDecoder().decode(BangumiItem.self, from: Data(json.utf8))
        #expect(item.eps == 12)
        #expect(item.platform == "TV")
        #expect(item.ratingTotal == 15667)
        #expect(item.episodeDuration == "")
    }

    /// 剧场版的"片长"能从 infobox 里正确提取。
    @Test("movie infobox: 片长 extracted as episodeDuration")
    func decodeMovieDuration() throws {
        let json = """
        {
            "id": 425,
            "name": "Movie Title",
            "name_cn": "电影标题",
            "summary": "",
            "date": "1980-03-15",
            "eps": 1,
            "platform": "剧场版",
            "images": {"large": "L", "common": "C", "medium": "M", "small": "S", "grid": "G"},
            "rating": {"rank": 100, "score": 8.0, "total": 500},
            "tags": [],
            "infobox": [
                {"key": "片长", "value": "92分钟"},
                {"key": "上映年度", "value": "1980年3月15日"}
            ]
        }
        """
        let item = try JSONDecoder().decode(BangumiItem.self, from: Data(json.utf8))
        #expect(item.eps == 1)
        #expect(item.platform == "剧场版")
        #expect(item.ratingTotal == 500)
        #expect(item.episodeDuration == "92分钟")
    }

    /// 搜索/趋势接口不返回 eps / platform / infobox 时应回落到默认值。
    @Test("missing eps, platform, infobox defaults gracefully")
    func decodeMissingSubjectFields() throws {
        let json = """
        {
            "id": 1,
            "name": "Minimal",
            "name_cn": "极简",
            "images": {"large": "L", "common": "C", "medium": "M", "small": "S", "grid": "G"},
            "rating": {"rank": 0, "score": 0}
        }
        """
        let item = try JSONDecoder().decode(BangumiItem.self, from: Data(json.utf8))
        #expect(item.eps == 0)
        #expect(item.platform == "")
        #expect(item.ratingTotal == 0)
        #expect(item.episodeDuration == "")
    }

    /// 编码后能往返解码（roundtrip）。
    @Test("roundtrip: encode then decode preserves all fields")
    func roundtripEncoding() throws {
        let original = BangumiItem(
            id: 7,
            name: "Original",
            nameCn: "原作",
            summary: "abc",
            airDate: "2025-04-01",
            rank: 3,
            ratingScore: 8.4,
            images: BangumiImages(
                large: "L", common: "C", medium: "M", small: "S", grid: "G"
            ),
            tags: [BangumiTag(name: "奇幻", count: 100)],
            ratingTotal: 999,
            eps: 24,
            platform: "TV"
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(BangumiItem.self, from: data)
        #expect(restored.id == original.id)
        #expect(restored.name == original.name)
        #expect(restored.nameCn == original.nameCn)
        #expect(restored.airDate == original.airDate)
        #expect(restored.rank == original.rank)
        #expect(restored.ratingScore == original.ratingScore)
        #expect(restored.images.large == "L")
        #expect(restored.tags.first?.name == "奇幻")
        #expect(restored.eps == 24)
        #expect(restored.platform == "TV")
        #expect(restored.ratingTotal == 999)
    }
}
