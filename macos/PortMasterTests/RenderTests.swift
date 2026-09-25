import AppKit
import SwiftUI
import XCTest
@testable import PortMaster

/// 离屏渲染诊断：把关键窗口尺寸渲染成 PNG，人工核对布局。
/// 渲染前启动真实采样并等待数据积累，输出到 /tmp/portmaster-*.png。
final class RenderTests: XCTestCase {
    @MainActor
    private func render(_ name: String, width: CGFloat, height: CGFloat, page: PrimaryView, resource: ResourceKind) async throws {
        let model = MonitorViewModel()
        model.start()
        defer { model.stop() }
        // 等待系统/网络采样与首轮进程/端口数据到达
        try await Task.sleep(nanoseconds: 3_000_000_000)
        model.page = page
        model.performance.resource = resource
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
    func testRenderCompactCPU() async throws {
        try await render("compact-cpu", width: 760, height: 520, page: .performance, resource: .cpu)
    }

    @MainActor
    func testRenderCompactNetwork() async throws {
        try await render("compact-network", width: 760, height: 520, page: .performance, resource: .network)
    }

    @MainActor
    func testRenderProcesses() async throws {
        try await render("processes", width: 1100, height: 720, page: .processes, resource: .cpu)
    }

    @MainActor
    func testRenderMemory() async throws {
        try await render("memory", width: 1100, height: 720, page: .performance, resource: .memory)
    }

    @MainActor
    func testRenderDisk() async throws {
        try await render("disk", width: 1100, height: 720, page: .performance, resource: .disk)
    }
}
