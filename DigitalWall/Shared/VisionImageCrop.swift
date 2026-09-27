import Foundation

struct VisionImageCropGeometry {
    let renderedSize: CGSize
    let origin: CGPoint
    let frameSize: CGSize
    let focalPoint: VisionImageFocalPoint

    init(imageSize: CGSize, frameSize: CGSize, focalPoint: VisionImageFocalPoint) {
        self.frameSize = CGSize(width: max(1, frameSize.width), height: max(1, frameSize.height))
        self.focalPoint = focalPoint
        let imageSize = CGSize(width: max(1, imageSize.width), height: max(1, imageSize.height))
        let scale = max(self.frameSize.width / imageSize.width, self.frameSize.height / imageSize.height)
        renderedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        origin = CGPoint(
            x: min(0, max(self.frameSize.width - renderedSize.width, self.frameSize.width / 2 - renderedSize.width * focalPoint.x)),
            y: min(0, max(self.frameSize.height - renderedSize.height, self.frameSize.height / 2 - renderedSize.height * focalPoint.y))
        )
    }

    var horizontalRange: ClosedRange<Double> {
        let inset = min(0.5, Double(frameSize.width / (2 * renderedSize.width)))
        return inset...(1 - inset)
    }

    var verticalRange: ClosedRange<Double> {
        let inset = min(0.5, Double(frameSize.height / (2 * renderedSize.height)))
        return inset...(1 - inset)
    }

    func focalPoint(afterDragging translation: CGSize) -> VisionImageFocalPoint {
        let x = min(0, max(frameSize.width - renderedSize.width, origin.x + translation.width))
        let y = min(0, max(frameSize.height - renderedSize.height, origin.y + translation.height))
        return VisionImageFocalPoint(
            x: renderedSize.width > frameSize.width + 0.001 ? Double((frameSize.width / 2 - x) / renderedSize.width) : focalPoint.x,
            y: renderedSize.height > frameSize.height + 0.001 ? Double((frameSize.height / 2 - y) / renderedSize.height) : focalPoint.y
        )
    }
}

struct VisionBoardCardLayout {
    let position: CGPoint
    let rotation: CGFloat
    let imageSize: CGSize

    init(index: Int, imageCount: Int, canvas: CGSize) {
        let featuredLayouts: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.22, 0.27, -4, 0.25), (0.50, 0.22, 3, 0.23),
            (0.78, 0.28, -2, 0.25), (0.31, 0.62, 2, 0.24),
            (0.66, 0.61, -3, 0.26), (0.10, 0.70, 4, 0.19),
            (0.88, 0.68, -4, 0.18), (0.50, 0.47, 1, 0.20)
        ]
        let layout: (CGFloat, CGFloat, CGFloat, CGFloat)
        let maximumCardHeight: CGFloat
        if imageCount <= featuredLayouts.count {
            layout = featuredLayouts[index]
            maximumCardHeight = canvas.height * 0.32
        } else {
            let columns = Int(ceil(sqrt(Double(imageCount))))
            let rows = Int(ceil(Double(imageCount) / Double(columns)))
            let row = index / columns
            let column = index % columns
            let imagesInRow = min(columns, imageCount - row * columns)
            let horizontalOffset = CGFloat(columns - imagesInRow) / 2
            let x = (CGFloat(column) + horizontalOffset + 0.5) / CGFloat(columns)
            let y = (CGFloat(row) + 0.5) / CGFloat(rows)
            layout = (
                0.08 + x * 0.84,
                0.08 + y * 0.76,
                CGFloat((index % 3) - 1) * 1.5,
                min(0.22, 0.78 / CGFloat(columns))
            )
            maximumCardHeight = canvas.height * min(0.24, 0.68 / CGFloat(rows))
        }
        imageSize = CGSize(width: min(max(canvas.width * layout.3, 190), 420), height: maximumCardHeight)
        position = CGPoint(x: canvas.width * layout.0, y: canvas.height * layout.1)
        rotation = layout.2
    }
}
