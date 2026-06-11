import Foundation
import AVFoundation
import os.log

/// 音频录制器 — AVFoundation PCM 16kHz 录音
final class AudioRecorder: NSObject, ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Data] = []
    private let logger = Logger(subsystem: "com.boxs.app", category: "AudioRecorder")

    /// 录制中的音频数据回调
    var onAudioData: ((Data) -> Void)?

    /// 是否正在录音
    @Published private(set) var isRecording = false

    // MARK: - 公开方法

    /// 请求麦克风权限
    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// 开始录音
    func startRecording() throws {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        audioEngine = AVAudioEngine()
        guard let audioEngine else { throw AudioError.engineCreationFailed }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // 转换为目标格式：PCM 16kHz, 16bit, 单声道
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioError.formatError
        }

        guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
            throw AudioError.converterError
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        try audioEngine.start()
        isRecording = true
        audioBuffer = []
        logger.info("录音开始")
    }

    /// 停止录音
    func stopRecording() {
        guard isRecording else { return }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false

        // 恢复音频会话
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        logger.info("录音结束")
    }

    // MARK: - 私有方法

    private func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        // 计算目标帧数
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: targetFrameCount
        ) else { return }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error else {
            logger.error("音频转换错误: \(error?.localizedDescription ?? "未知")")
            return
        }

        // 将 PCM 数据转为 Data
        if let channelData = outputBuffer.int16ChannelData {
            let data = Data(
                bytes: channelData[0],
                count: Int(outputBuffer.frameLength) * 2 // 16bit = 2 bytes
            )
            onAudioData?(data)
        }
    }
}

// MARK: - 错误

enum AudioError: LocalizedError {
    case engineCreationFailed
    case formatError
    case converterError
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .engineCreationFailed: return "音频引擎创建失败"
        case .formatError: return "音频格式不支持"
        case .converterError: return "音频转换器创建失败"
        case .permissionDenied: return "麦克风权限被拒绝"
        }
    }
}
