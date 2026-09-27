import Foundation

@main
enum VisionImageCropTests {
    static func main() throws {
        let legacyJSON = Data("""
        {"id":"11111111-1111-1111-1111-111111111111","fileName":"portrait.png","phrase":"Keep going","displayMode":"fill"}
        """.utf8)
        var image = try JSONDecoder().decode(VisionImage.self, from: legacyJSON)
        precondition(image.focalPoint == .center, "Existing Fill images must keep their centered crop")
        image.focalPoint = VisionImageFocalPoint(x: 0.25, y: 0.75)
        let restored = try JSONDecoder().decode(VisionImage.self, from: JSONEncoder().encode(image))
        precondition(restored == image, "Saving a focal point must preserve image identity, caption, and display mode")

        let invalidPoint = try JSONDecoder().decode(VisionImageFocalPoint.self, from: Data("{\"x\":-10,\"y\":20}".utf8))
        precondition(invalidPoint == VisionImageFocalPoint(x: 0, y: 1))
        precondition(VisionImageFocalPoint(x: .nan, y: .infinity) == .center)

        let portrait = VisionImageCropGeometry(
            imageSize: CGSize(width: 100, height: 200),
            frameSize: CGSize(width: 100, height: 100),
            focalPoint: .center
        )
        precondition(portrait.origin.x == 0 && portrait.origin.y == -50)
        let dragged = portrait.focalPoint(afterDragging: CGSize(width: 100, height: -25))
        precondition(dragged == VisionImageFocalPoint(x: 0.5, y: 0.625), "Dragging up reveals the lower part without shifting the uncropped axis")
        precondition(portrait.focalPoint(afterDragging: CGSize(width: 0, height: -10000)).y == 0.75)
        precondition(portrait.focalPoint(afterDragging: CGSize(width: 0, height: 10000)).y == 0.25)

        let larger = VisionImageCropGeometry(
            imageSize: CGSize(width: 100, height: 200),
            frameSize: CGSize(width: 400, height: 400),
            focalPoint: dragged
        )
        precondition(larger.origin.x == 0 && larger.origin.y == -300, "The crop must scale with the frame")

        for imageSize in [CGSize(width: 100, height: 200), CGSize(width: 200, height: 100), CGSize(width: 100, height: 100)] {
            for frameSize in [CGSize(width: 100, height: 100), CGSize(width: 400, height: 200), CGSize(width: 200, height: 400)] {
                for point in [VisionImageFocalPoint.center, VisionImageFocalPoint(x: 0, y: 0), VisionImageFocalPoint(x: 1, y: 1), dragged] {
                    let geometry = VisionImageCropGeometry(imageSize: imageSize, frameSize: frameSize, focalPoint: point)
                    assertCovered(geometry)
                    let focus = CGPoint(
                        x: geometry.origin.x + geometry.renderedSize.width * point.x,
                        y: geometry.origin.y + geometry.renderedSize.height * point.y
                    )
                    precondition(focus.x >= -0.001 && focus.x <= frameSize.width + 0.001)
                    precondition(focus.y >= -0.001 && focus.y <= frameSize.height + 0.001, "The chosen focus must stay visible across frame shapes")
                    for translation in [CGSize(width: -10000, height: 10000), CGSize(width: 10000, height: -10000)] {
                        let panned = geometry.focalPoint(afterDragging: translation)
                        assertCovered(VisionImageCropGeometry(imageSize: imageSize, frameSize: frameSize, focalPoint: panned))
                    }
                }
            }
        }

        let canvas = CGSize(width: 1920, height: 1080)
        for count in [1, 8, 9, 40] {
            for index in 0..<count {
                let layout = VisionBoardCardLayout(index: index, imageCount: count, canvas: canvas)
                precondition(layout.imageSize.width > 0 && layout.imageSize.height > 0)
                precondition(layout.position.x > 0 && layout.position.x < canvas.width)
                precondition(layout.position.y > 0 && layout.position.y < canvas.height)
            }
        }
        print("PASS: crop migration, persistence, dragging, frame coverage, and focus across frame shapes")
    }

    private static func assertCovered(_ geometry: VisionImageCropGeometry) {
        precondition(geometry.origin.x <= 0.001 && geometry.origin.y <= 0.001)
        precondition(geometry.origin.x + geometry.renderedSize.width >= geometry.frameSize.width - 0.001)
        precondition(geometry.origin.y + geometry.renderedSize.height >= geometry.frameSize.height - 0.001, "Dragging must never expose empty edges")
    }
}
