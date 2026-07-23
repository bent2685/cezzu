import SwiftUI

/// 进度条的几何换算。抽出来是为了脱离 SwiftUI 直接测边界条件。
enum PlayerProgressBarGeometry {
    /// 播放进度占比，`duration` 无效时按 0 处理。
    static func fraction(position: TimeInterval, duration: TimeInterval) -> Double {
        guard duration.isFinite, duration > 0, position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// 把拖拽落点换算回时间，超出轨道两端时夹紧。
    static func position(atX x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0, duration.isFinite, duration > 0 else { return 0 }
        let ratio = min(max(Double(x / width), 0), 1)
        return ratio * duration
    }

    /// 把手中心的 x —— 两端各留半个把手宽，避免圆头被切掉。
    static func thumbCenterX(fraction: Double, width: CGFloat, thumbWidth: CGFloat) -> CGFloat {
        let half = thumbWidth / 2
        guard width > thumbWidth else { return width / 2 }
        return half + CGFloat(min(max(fraction, 0), 1)) * (width - thumbWidth)
    }

    /// 预览窗跟着把手走，但拖到两端时要夹住，不能飘出轨道之外。
    static func previewCenterX(
        thumbCenterX: CGFloat,
        width: CGFloat,
        previewWidth: CGFloat
    ) -> CGFloat {
        let half = previewWidth / 2
        guard width > previewWidth else { return width / 2 }
        return min(max(thumbCenterX, half), width - half)
    }
}

/// 播放进度条：已播 / 已缓冲 / 未加载三段 + 竖向胶囊把手。
///
/// 不用原生 `Slider` 是因为它的把手只能是圆点，做不出稿子里高于轨道的竖条。
struct PlayerProgressBar<Preview: View>: View {
    @Binding var position: TimeInterval
    let duration: TimeInterval
    let bufferedTime: TimeInterval?
    /// 语义对齐 `Slider(onEditingChanged:)`：拖拽开始传 true，结束传 false。
    let onEditingChanged: (Bool) -> Void
    /// 拖拽期间浮在把手正上方的预览窗。宽度由 `previewWidth` 固定，方便夹边。
    @ViewBuilder let preview: () -> Preview

    @State private var isDragging = false

    private let previewWidth: CGFloat = 168
    /// 预览窗底边与轨道之间留出的抬升量（含预览自身高度）。
    private let previewLift: CGFloat = 84
    private let thumbWidth: CGFloat = 6
    private let idleTrackHeight: CGFloat = 6
    private let activeTrackHeight: CGFloat = 10
    private let thumbOvershoot: CGFloat = 12

    private var trackHeight: CGFloat {
        isDragging ? activeTrackHeight : idleTrackHeight
    }

    private var thumbHeight: CGFloat {
        trackHeight + thumbOvershoot
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let playedFraction = PlayerProgressBarGeometry.fraction(
                position: position,
                duration: duration
            )
            let bufferedFraction = PlayerProgressBarGeometry.fraction(
                position: bufferedTime ?? 0,
                duration: duration
            )

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.28))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(.white.opacity(0.45))
                    .frame(width: width * bufferedFraction, height: trackHeight)

                Capsule()
                    .fill(.white)
                    .frame(width: width * playedFraction, height: trackHeight)

                let thumbX = PlayerProgressBarGeometry.thumbCenterX(
                    fraction: playedFraction,
                    width: width,
                    thumbWidth: thumbWidth
                )

                Capsule()
                    .fill(.white)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .position(x: thumbX, y: proxy.size.height / 2)

                if isDragging {
                    preview()
                        .frame(width: previewWidth)
                        .position(
                            x: PlayerProgressBarGeometry.previewCenterX(
                                thumbCenterX: thumbX,
                                width: width,
                                previewWidth: previewWidth
                            ),
                            y: proxy.size.height / 2
                        )
                        // 浮到轨道上方，不参与布局也不吃手势。
                        .offset(y: -previewLift)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        position = PlayerProgressBarGeometry.position(
                            atX: value.location.x,
                            width: width,
                            duration: duration
                        )
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        // 固定外框高度，拖拽时轨道涨高不会顶动上下的标题与按钮。
        .frame(height: activeTrackHeight + thumbOvershoot)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue(Text("\(Int(position)) 秒，共 \(Int(duration)) 秒"))
    }
}
