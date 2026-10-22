import SwiftUI
import AppKit

struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(Color(white: 0.85))
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Color(white: 1, opacity: 0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(white: 1, opacity: 0.14), lineWidth: 1))
    }
}

struct MiniDesktop: View {
    var body: some View {
        ZStack(alignment: .trailing) {
            // Wallpaper
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.11, green: 0.17, blue: 0.48), Color(red: 0.04, green: 0.06, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(
                        RadialGradient(colors: [Color(red: 0.5, green: 0.72, blue: 1).opacity(0.75), .clear], center: .init(x: 0.15, y: 0.0), startRadius: 0, endRadius: 320)))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(
                        RadialGradient(colors: [Color(red: 1, green: 0.56, blue: 0.64).opacity(0.55), .clear], center: .init(x: 0.95, y: 0.2), startRadius: 0, endRadius: 260)))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(white: 1, opacity: 0.12), lineWidth: 1))
            // Menu bar
            VStack { Rectangle().fill(Color(white: 0, opacity: 0.25)).frame(height: 14); Spacer() }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            // A window, half-way into the right edge
            HStack(spacing: 0) {
                Spacer()
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.98))
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 9, height: 9)
                            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 9, height: 9)
                            Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 9, height: 9)
                            Spacer()
                        }.padding(10).background(Color(white: 0.93))
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach([0.8, 1.0, 0.55, 0.9, 0.7], id: \.self) { w in
                                Capsule().fill(Color(white: 0.84)).frame(width: 150 * w, height: 9)
                            }
                        }.padding(14)
                    }
                }
                .frame(width: 200, height: 150)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                .offset(x: 70)
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                    .offset(x: 70 + 14)
                Spacer().frame(width: 150)
            }
            .padding(.top, 10)
            // The tab on the edge
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(Color(red: 1, green: 0.71, blue: 0.23))
                .frame(width: 34, height: 110)
                .overlay(alignment: .top) {
                    Image(nsImage: NSImage(contentsOfFile: CommandLine.arguments[1])!)
                        .resizable().frame(width: 22, height: 22).padding(.top, 10)
                }
                .shadow(color: .black.opacity(0.35), radius: 10, x: -4)
                .offset(x: 0, y: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct Card: View {
    let icon: NSImage
    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.09, blue: 0.10)
            // Ambient glow, as on the website's demo
            RadialGradient(colors: [Color(red: 0.25, green: 0.45, blue: 1).opacity(0.28), .clear], center: .init(x: 0.05, y: 0.1), startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color(red: 1, green: 0.68, blue: 0.2).opacity(0.18), .clear], center: .init(x: 0.95, y: 1.0), startRadius: 0, endRadius: 600)

            HStack(alignment: .center, spacing: 56) {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 22) {
                        Image(nsImage: icon).resizable().frame(width: 112, height: 112)
                        Text("Sticky Windows")
                            .font(.system(size: 54, weight: .bold)).tracking(-1.5)
                            .foregroundStyle(.white)
                    }
                    Text("Park any window on the\nedge of your screen.")
                        .font(.system(size: 40, weight: .semibold)).tracking(-0.8)
                        .foregroundStyle(Color(white: 0.92))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Pill(text: "macOS 15+")
                        Pill(text: "Free")
                        Pill(text: "stickywindows.com")
                    }
                }
                .frame(width: 700, alignment: .leading)
                MiniDesktop().frame(width: 340, height: 250)
            }
            .padding(.horizontal, 64)
        }
        .frame(width: 1200, height: 630)
    }
}

@main
struct Main {
    @MainActor static func main() {
        let iconPath = CommandLine.arguments[1]
        let out = CommandLine.arguments[2]
        let icon = NSImage(contentsOfFile: iconPath)!
        let renderer = ImageRenderer(content: Card(icon: icon))
        renderer.scale = 2
        let image = renderer.nsImage!
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        // Downsample to exactly 1200x630 for the og:image (2x master kept too)
        let png2x = rep.representation(using: .png, properties: [:])!
        try! png2x.write(to: URL(fileURLWithPath: out + "@2x.png"))
        let final = NSImage(size: NSSize(width: 1200, height: 630))
        final.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: 1200, height: 630))
        final.unlockFocus()
        let data = NSBitmapImageRep(data: final.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: out + ".png"))
        print("wrote", out + ".png")
    }
}
