@preconcurrency import AVFAudio
import Foundation

public final class PCMConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    public init(
        inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat
    ) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterUnavailable
        }
        converter.primeMethod = .none
        self.converter = converter
        self.outputFormat = outputFormat
    }

    public func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> Data? {
        let inputRate = inputBuffer.format.sampleRate
        guard inputRate > 0 else {
            throw AudioCaptureError.inputFormatUnavailable
        }

        let estimatedFrames = max(
            Int(inputBuffer.frameLength),
            Int(ceil(Double(inputBuffer.frameLength) * outputFormat.sampleRate / inputRate)) + 1
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(estimatedFrames)
        ) else {
            throw AudioCaptureError.outputFormatUnavailable
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) {
            _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        if status == .error {
            let message = conversionError?.localizedDescription ?? "unknown converter error"
            throw AudioCaptureError.conversionFailed(message)
        }

        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        guard byteCount > 0,
              let channels = outputBuffer.int16ChannelData else {
            return nil
        }
        return Data(bytes: channels.pointee, count: byteCount)
    }

    public func finish() throws -> Data? {
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: 4_096
        ) else {
            throw AudioCaptureError.outputFormatUnavailable
        }

        var suppliedEnd = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) {
            _, inputStatus in
            if suppliedEnd {
                inputStatus.pointee = .noDataNow
            } else {
                suppliedEnd = true
                inputStatus.pointee = .endOfStream
            }
            return nil
        }
        if status == .error {
            let message = conversionError?.localizedDescription ?? "unknown converter error"
            throw AudioCaptureError.conversionFailed(message)
        }

        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        guard byteCount > 0,
              let channels = outputBuffer.int16ChannelData else {
            return nil
        }
        return Data(bytes: channels.pointee, count: byteCount)
    }
}
