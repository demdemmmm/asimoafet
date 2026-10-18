// Godot Movie Maker AVI (MJPEG + PCM s16) -> MP4 (H.264 + AAC), yalnız Apple AVFoundation ile.
// Kullanım: avi2mp4 girdi.avi çıktı.mp4
import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import CoreMedia

let args = CommandLine.arguments
guard args.count == 3 else { print("kullanım: avi2mp4 in.avi out.mp4"); exit(1) }
let data = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .alwaysMapped)
let outURL = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: outURL)

func u32(_ o: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }) }
func tag(_ o: Int) -> String { String(decoding: data[o..<o + 4], as: UTF8.self) }

var video: [(Int, Int)] = []
var audioRanges: [(Int, Int)] = []
var fps = 30
var width = 1920, height = 1080
var sampleRate = 48000, channels = 2

func walk(_ start: Int, _ end: Int) {
    var o = start
    while o + 8 <= end {
        let id = tag(o)
        let size = u32(o + 4)
        if id == "RIFF" || id == "LIST" {
            walk(o + 12, min(o + 8 + size, end))
        } else if id == "avih" {
            let usPerFrame = u32(o + 8)
            if usPerFrame > 0 { fps = Int((1_000_000.0 / Double(usPerFrame)).rounded()) }
            width = u32(o + 8 + 32)
            height = u32(o + 8 + 36)
        } else if id == "strf" && size == 16 {
            channels = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o + 10, as: UInt16.self) })
            sampleRate = u32(o + 12)
        } else if id.hasSuffix("dc") || id.hasSuffix("db") {
            video.append((o + 8, size))
        } else if id.hasSuffix("wb") {
            audioRanges.append((o + 8, size))
        }
        o += 8 + size + (size & 1)
    }
}
walk(0, data.count)
print("kare: \(video.count)  fps: \(fps)  boyut: \(width)x\(height)  ses: \(sampleRate) Hz \(channels) kanal")

let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 14_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: fps * 2,
    ],
])
vIn.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
])
let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
    AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 192_000,
])
aIn.expectsMediaDataInRealTime = false
writer.add(vIn)
writer.add(aIn)
guard writer.startWriting() else { print("yazıcı açılamadı: \(String(describing: writer.error))"); exit(1) }
writer.startSession(atSourceTime: .zero)

// Ses: tüm PCM tek tamponda, 4800 karelik parçalar halinde.
var pcm = Data()
for (o, s) in audioRanges { pcm.append(data[o..<o + s]) }
let bytesPerFrame = 2 * channels
let totalFrames = pcm.count / bytesPerFrame
var asbd = AudioStreamBasicDescription(mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
    mBytesPerPacket: UInt32(bytesPerFrame), mFramesPerPacket: 1, mBytesPerFrame: UInt32(bytesPerFrame),
    mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
var fmt: CMAudioFormatDescription?
CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
    magicCookie: nil, extensions: nil, formatDescriptionOut: &fmt)

let group = DispatchGroup()
var vIndex = 0
var aFrame = 0
let space = CGColorSpaceCreateDeviceRGB()

group.enter()
vIn.requestMediaDataWhenReady(on: DispatchQueue(label: "video")) {
    while vIn.isReadyForMoreMediaData {
        if vIndex >= video.count {
            vIn.markAsFinished()
            group.leave()
            return
        }
        let (o, s) = video[vIndex]
        let jpeg = data[o..<o + s] as CFData
        guard let src = CGImageSourceCreateWithData(jpeg, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let pool = adaptor.pixelBufferPool else { vIndex += 1; continue }
        var pbOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut)
        guard let pb = pbOut else { vIndex += 1; continue }
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pb, [])
        adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(vIndex), timescale: CMTimeScale(fps)))
        vIndex += 1
    }
}

group.enter()
aIn.requestMediaDataWhenReady(on: DispatchQueue(label: "audio")) {
    while aIn.isReadyForMoreMediaData {
        if aFrame >= totalFrames {
            aIn.markAsFinished()
            group.leave()
            return
        }
        let n = min(4800, totalFrames - aFrame)
        let chunk = pcm.subdata(in: aFrame * bytesPerFrame..<(aFrame + n) * bytesPerFrame)
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: chunk.count, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: chunk.count, flags: 0, blockBufferOut: &block)
        chunk.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: chunk.count)
        }
        var sb: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: fmt!,
            sampleCount: n, presentationTimeStamp: CMTime(value: CMTimeValue(aFrame), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sb)
        aIn.append(sb!)
        aFrame += n
    }
}

group.wait()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status == .completed ? "tamam: \(outURL.path)" : "hata: \(String(describing: writer.error))")
