import UIKit

/// A view that displays OCR text regions as selectable overlays on top of an image.
///
/// This view synchronizes with the PhotoView's scale and position to ensure accurate
/// placement of text bounding boxes during zoom and pan operations. It uses the
/// transform matrix from the image viewer to maintain proper alignment.
///
/// ## Usage
///
/// ```swift
/// let overlay = OCROverlayView(frame: imageView.bounds)
/// overlay.update(with: recognizedBlocks, imageSize: originalImageSize)
/// overlay.updateTransform(viewerTransform, scale: currentScale)
/// ```
class OCROverlayView: UIView {
    
    /// The current transform applied by the image viewer (for sync).
    private var currentTransform: CGAffineTransform = .identity
    
    /// The scale factor from the image viewer.
    private var currentScale: CGFloat = 1.0
    
    /// The original size of the image in pixels.
    private var imageSize: CGSize = .zero
    
    /// The recognized text blocks to display.
    private var blocks: [RecognizedTextBlock] = []
    
    /// The alpha value for overlay elements.
    private static let overlayAlpha: CGFloat = 0.4
    
    /// The border color for text bounding boxes.
    private static let borderColor: UIColor = .systemBlue
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }
    
    private func configureView() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    
    // MARK: - Public API
    
    /// Update the overlay with new text blocks and image size.
    ///
    /// - Parameters:
    ///   - blocks: Array of recognized text blocks to display.
    ///   - imageSize: Original image size in pixels (used for coordinate conversion).
    func update(with blocks: [RecognizedTextBlock], imageSize: CGSize) {
        self.blocks = blocks
        self.imageSize = imageSize
        setNeedsDisplay()
    }
    
    /// Update the transform and scale from the image viewer to sync overlays.
    ///
    /// - Parameters:
    ///   - transform: The current CGAffineTransform applied by the image viewer.
    ///   - scale: The current scale factor (1.0 = original size).
    func updateTransform(_ transform: CGAffineTransform, scale: CGFloat) {
        self.currentTransform = transform
        self.currentScale = scale
        setNeedsDisplay()
    }
    
    // MARK: - Drawing
    
    override func draw(_ rect: CGRect) {
        guard !blocks.isEmpty else { return }
        
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        
        // Apply the viewer's transform and scale to sync overlays with image
        var transform = currentTransform
        transform = transform.scaledBy(x: currentScale, y: currentScale)
        context?.concatenate(transform)
        
        // Calculate scaling from image pixels to view coordinates
        let scaleX = bounds.width / imageSize.width
        let scaleY = bounds.height / imageSize.height
        
        for block in blocks {
            drawTextBlock(block, with: context, scaleX: scaleX, scaleY: scaleY)
        }
        
        context?.restoreGState()
    }
    
    private func drawTextBlock(_ block: RecognizedTextBlock, with context: CGContext?, scaleX: CGFloat, scaleY: CGFloat) {
        guard let context = context else { return }
        
        // Convert normalized coordinates (0-1) to view coordinates
        let x1 = block.boundingBox[0] * imageSize.width * scaleX
        let y1 = block.boundingBox[1] * imageSize.height * scaleY
        let x2 = block.boundingBox[2] * imageSize.width * scaleX
        let y2 = block.boundingBox[3] * imageSize.height * scaleY
        let x3 = block.boundingBox[4] * imageSize.width * scaleX
        let y3 = block.boundingBox[5] * imageSize.height * scaleY
        let x4 = block.boundingBox[6] * imageSize.width * scaleX
        let y4 = block.boundingBox[7] * imageSize.height * scaleY
        
        // Create path for the bounding box (quadrilateral)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        path.addLine(to: CGPoint(x: x3, y: y3))
        path.addLine(to: CGPoint(x: x4, y: y4))
        path.close()
        
        // Draw filled bounding box
        OCROverlayView.borderColor.withAlpha(OCROverlayView.overlayAlpha).setFill()
        context.addPath(path.cgPath)
        context.fillPath()
        
        // Draw border
        OCROverlayView.borderColor.setStroke()
        path.lineWidth = 2.0
        context.addPath(path.cgPath)
        context.strokePath()
    }
    
    // MARK: - Hit Testing
    
    /// Determine which text block was tapped (if any).
    ///
    /// - Parameters:
    ///   - point: The touch point in this view's coordinate system.
    /// - Returns: The index of the touched text block, or nil if no block was touched.
    func getTextBlock(at point: CGPoint) -> Int? {
        guard !blocks.isEmpty else { return nil }
        
        // Reverse transform to get image coordinates
        let inverseTransform = currentTransform.inverted()
        let transformedPoint = point.applying(inverseTransform)
        
        let scaleX = bounds.width / imageSize.width
        let scaleY = bounds.height / imageSize.height
        
        for (index, block) in blocks.enumerated() {
            if isPointInTextBlock(transformedPoint, block: block, scaleX: scaleX, scaleY: scaleY) {
                return index
            }
        }
        
        return nil
    }
    
    private func isPointInTextBlock(_ point: CGPoint, block: RecognizedTextBlock, scaleX: CGFloat, scaleY: CGFloat) -> Bool {
        // Convert normalized coordinates to view coordinates (before scale transform)
        let x1 = block.boundingBox[0] * imageSize.width
        let y1 = block.boundingBox[1] * imageSize.height
        let x2 = block.boundingBox[2] * imageSize.width
        let y2 = block.boundingBox[3] * imageSize.height
        let x3 = block.boundingBox[4] * imageSize.width
        let y3 = block.boundingBox[5] * imageSize.height
        let x4 = block.boundingBox[6] * imageSize.width
        let y4 = block.boundingBox[7] * imageSize.height
        
        // Create polygon from vertices
        let points: [CGPoint] = [
            CGPoint(x: x1, y: y1),
            CGPoint(x: x2, y: y2),
            CGPoint(x: x3, y: y3),
            CGPoint(x: x4, y: y4)
        ]
        
        // Use even-odd rule to check if point is inside polygon
        let path = UIBezierPath()
        path.move(to: points[0])
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }
        path.close()
        
        return path.contains(point)
    }
}
