// SPDX-License-Identifier: LGPL-2.1-or-later
// The Mac Cuvee runs on, and the bottle settings recommended for it (Apple Silicon only for now).
import Darwin

enum Device {
    /// "Apple M4 Max", or nil on an Intel Mac.
    static let chip: String? = {
        guard sysctlInt("hw.optional.arm64") == 1 else { return nil }
        return sysctlString("machdep.cpu.brand_string")
    }()

    /// DXMT drives Metal directly (one translation layer instead of wined3d + MoltenVK). MetalFX renders fewer pixels
    /// and upscales them: worth it on a base chip, while Pro, Max and Ultra GPUs can afford native resolution.
    static var recommended: (graphics: Graphics, metalFX: Bool)? {
        guard let chip else { return nil }
        let bigGPU = ["Pro", "Max", "Ultra"].contains { chip.contains($0) }
        return (.dxmt, !bigGPU)
    }

    static var reason: String {
        guard let rec = recommended else { return "" }
        return rec.metalFX
            ? tr("Metal direct, et MetalFX calcule l'image plus petite puis l'agrandit : plus d'images par seconde sur une puce de base.",
                 "Direct Metal, and MetalFX renders a smaller image then upscales it: more frames per second on a base chip.")
            : tr("Metal direct, sans mise à l'échelle : ta puce a assez de cœurs graphiques pour la pleine résolution.",
                 "Direct Metal, no upscaling: your chip has enough GPU cores for native resolution.")
    }

    private static func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
