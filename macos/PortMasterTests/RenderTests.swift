import AppKit
import SwiftUI
import XCTest
@testable import PortMaster

/// 离屏渲染诊断：把关键窗口尺寸渲染成 PNG，人工核对布局。
final class RenderTests: XCTestCase {
    @MainActor
    private func render(_ name: String, width: CGFloat, height: CGFloat, page: PrimaryView, resource: ResourceKind) throws {
        let model = MonitorViewModel()
        model.page = page
        model.resource = resource
        let view = ContentView(model: model).frame(width: width, height: height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("render failed: \(name)")
            return
        }
        try png.write(to: URL(fileURLWithPath: "/tmp/portmaster-\(name).png"))
    }

    @MainActor
    func testRenderCompactCPU() throws {
        try render("compact-cpu", width: 760, height: 520, page: .performance, resource: .cpu)
    }

    @MainActor
    func testRenderCompactNetwork() throws {
        try render("compact-network", width: 760, height: 520, page: .performance, resource: .network)
    }
}
