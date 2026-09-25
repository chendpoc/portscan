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
        let view = ContentView(model: model, showsBrandLaunch: false).frame(width: width, height: height)
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

    /// 吃豆人朝向定向：嘴（缺口）必须朝右对着豆子轨道。
    @MainActor
    func testRenderPacman() throws {
        let view = PacmanShape(openFraction: 0.35)
            .fill(Theme.accent)
            .frame(width: 200, height: 200)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("render failed: pacman")
            return
        }
        try png.write(to: URL(fileURLWithPath: "/tmp/pacman.png"))
    }

    /// 品牌首启帧：验证品牌层铺满全窗口（曾经挂在塌缩的 VStack 上只显示一角）。
    /// 像素断言：四角必须是品牌底色；中心区域必须存在 accent 蓝（图腾在场）。
    @MainActor
    func testRenderBrandLaunch() async throws {
        UserDefaults.standard.removeObject(forKey: "pm.didLaunchBrand")
        let model = MonitorViewModel()
        let view = ContentView(model: model).frame(width: 1100, height: 720)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("render failed: brand")
            return
        }
        try png.write(to: URL(fileURLWithPath: "/tmp/portmaster-brand.png"))

        // 四角（留 4px 边距）必须是品牌底色 #ECECEE（容差 ±6，色彩管理有微偏）
        let corners = [(4, 4), (1095, 4), (4, 715), (1095, 715)]
        for (x, y) in corners {
            let pixel = Self.pixel(rep, x, y)
            XCTAssertEqual(pixel.r, 236, accuracy: 6, "角 (\(x),\(y)) 红色通道异常：\(pixel)")
            XCTAssertEqual(pixel.g, 236, accuracy: 6, "角 (\(x),\(y)) 绿色通道异常：\(pixel)")
            XCTAssertEqual(pixel.b, 238, accuracy: 6, "角 (\(x),\(y)) 蓝色通道异常：\(pixel)")
        }
        // 中部 300×260 区域内存在 accent 蓝（#0A84FF 系）像素（图腾/进度条所在带）
        var accentFound = false
        outer: for y in stride(from: 230, to: 490, by: 4) {
            for x in stride(from: 400, to: 700, by: 4) {
                let pixel = Self.pixel(rep, x, y)
                if pixel.b > 180, pixel.b > pixel.r + 40 {
                    accentFound = true
                    break outer
                }
            }
        }
        XCTAssertTrue(accentFound, "中部区域未找到品牌图腾的 accent 蓝像素")
    }

    /// 读取位图像素（假定 RGBA 8bit，ImageRenderer 输出即此格式）。
    private static func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        guard let data = rep.bitmapData, rep.bitsPerPixel == 32 else { return (0, 0, 0) }
        let offset = y * rep.bytesPerRow + x * 4
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
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
