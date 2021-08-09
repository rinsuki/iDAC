//
//  MainViewController.swift
//  iDAC
//
//  Created by user on 2021/08/08.
//

import UIKit
import AVKit
import Network
import AudioToolbox
import SnapKit

class MainViewController: UIViewController {
    init(connection: NWConnection) {
        self.conn = connection
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var conn: NWConnection

    override func loadView() {
        view = UIView()
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        let stackView = UIStackView(arrangedSubviews: [
            recvCountLabel,
            sendCountLabel,
            bufferMaxSlider,
            playBufferLabel,
            skipButton
        ])
        stackView.axis = .vertical
        view.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalToSuperview().inset(16)
        }
        let monospaceFont: UIFont
        if #available(iOS 13.0, *) {
            monospaceFont = .monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
        } else {
            monospaceFont = UIFont(name: "Menlo", size: UIFont.systemFontSize)!
        }
        recvCountLabel.font = monospaceFont
        sendCountLabel.font = monospaceFont
        playBufferLabel.font = monospaceFont
        skipButton.backgroundColor = skipButton.tintColor
        skipButton.setTitleColor(.white, for: .normal)
        skipButton.setTitle("Stop add sounds to buffer while tapping here", for: .normal)
        skipButton.contentEdgeInsets = .init(top: 16, left: 16, bottom: 16, right: 16)
        bufferMaxSlider.minimumValue = 10
        bufferMaxSlider.maximumValue = 100
        bufferMaxSlider.value = 20
        bufferMaxSlider.isContinuous = true
    }
    
    let skipButton = UIButton(type: .custom)
    var skipNow: Bool {
        return skipNowByButton || skipNowByLargeBuffer
    }
    var skipNowByButton = false
    var skipNowByLargeBuffer = false
    
    @objc func startSkip() {
        skipNowByButton = true
    }
    
    @objc func endSkip() {
        skipNowByButton = false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        skipButton.addTarget(self, action: #selector(startSkip), for: .touchDown)
        skipButton.addTarget(self, action: #selector(endSkip), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(endSkip), for: .touchUpOutside)
        navigationItem.rightBarButtonItem = .init(title: "Stop", style: .done, target: self, action: #selector(close))
        bufferMaxSlider.addTarget(self, action: #selector(bufferMaxChanged), for: .valueChanged)

        setupAudio()
        RunLoop.main.add(timer, forMode: .default)
        RunLoop.main.add(timerHighFreq, forMode: .default)
        if #available(iOS 13.0, *) {
            isModalInPresentation = true
        }
    }
    
    let recvCountLabel = UILabel()
    let sendCountLabel = UILabel()
    let playBufferLabel = UILabel()
    var recvCount = 0
    var sendCount = 0
    var playBufferMilliSec: Double = 0
    lazy var timer = Timer(timeInterval: 1, target: self, selector: #selector(updateCounts), userInfo: nil, repeats: true)
    lazy var timerHighFreq = Timer(timeInterval: 0.1, target: self, selector: #selector(updateCountsHighFreq), userInfo: nil, repeats: true)
    
    @objc func updateCounts() {
        recvCountLabel.text = "Recv: \(recvCount)packet/sec (≒\(String(format: "%.1f", 1000.0/Double(recvCount)))ms/packet)"
        sendCountLabel.text = "Send: \(sendCount)packet/sec (≒\(String(format: "%.1f", 1000.0/Double(sendCount)))ms/packet)"
        recvCount = 0
        sendCount = 0
    }
    
    @objc func updateCountsHighFreq() {
        playBufferLabel.text = "Buffer: \(String(format: "%.1f", playBufferMilliSec))msec (max: \(bufferMaxMsec)msec)"
    }
    
    var bufferMaxMsec: Double = 1000/30
    let bufferMaxSlider = UISlider()

    @objc func bufferMaxChanged() {
        let v = round(bufferMaxSlider.value / 5) * 5
        bufferMaxSlider.value = v
        bufferMaxMsec = Double(v)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        audioEngine.stop()
        conn.cancel()
    }
    
    @objc func close() {
        dismiss(animated: true, completion: nil)
    }
    
    // MARK: Audio things

    let audioEngine = AVAudioEngine()
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
    let player = AVAudioPlayerNode()
    let networkQueue = DispatchQueue(label: "jp.pronama.iDAC.NetworkQueue", qos: .userInteractive)

    func setupAudio() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        print(inputFormat)
        let bufferMillisecond = 5
        let bufferSize = AVAudioFrameCount(ceil(inputFormat.sampleRate / 1000 * Double(bufferMillisecond)))
        let mixer = AVAudioMixerNode()
        audioEngine.attach(player)
        audioEngine.attach(mixer)
        audioEngine.connect(player, to: mixer, format: format)
        audioEngine.connect(mixer, to: audioEngine.outputNode, format: format)
        audioEngine.prepare()
        print(bufferSize)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [self] buffer, time in
            buffer.frameLength = bufferSize
            guard let floatData = buffer.floatChannelData?.pointee else {
                print("can't find floatChannelData")
                return
            }
            guard !skipNow else {
                return
            }
            self.sendCount += 1
            conn.send(content: Data(bytes: floatData, count: Int(buffer.frameLength) * MemoryLayout<Float>.size), completion: .contentProcessed { [self] error in
                if let error = error {
                    print(error)
                    conn.cancel()
                    audioEngine.stop()
                }
            })
        }
        conn.start(queue: networkQueue)
        try! audioEngine.start()
        receive()
        player.play()
    }
    
    func receive() {
        conn.receive(minimumIncompleteLength: 0, maximumLength: 1024, completion: received)
    }
    
    func received(_ data: Data?, context: NWConnection.ContentContext?, _ flag: Bool, _ error: NWError?) {
        if let error = error {
            print(error)
            conn.cancel()
            audioEngine.stop()
            return
        }
        guard let data = data else {
            print("data is not available")
            conn.cancel()
            audioEngine.stop()
            return
        }
        let f32: [Float32] = data.withUnsafeBytes {
            Array($0.bindMemory(to: Float32.self))
        }
        let dataFrameLength = data.count / (Int(format.channelCount) * MemoryLayout<Float32>.size)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: .init(dataFrameLength))!
        buffer.frameLength = .init(dataFrameLength)
        for i in 0..<Int(format.channelCount) {
            let d = buffer.floatChannelData![i]
            for j in 0..<Int(dataFrameLength) {
                d[j] = f32[(j*Int(format.channelCount))+i]
            }
        }
        self.recvCount += 1
        if skipNowByLargeBuffer {
            if playBufferMilliSec < (bufferMaxMsec / 2) {
                skipNowByLargeBuffer = false
            }
        } else if playBufferMilliSec > bufferMaxMsec {
            skipNowByLargeBuffer = true
        }
        if !skipNow {
            let msec = Double(dataFrameLength * 1000) / format.sampleRate
            self.playBufferMilliSec += msec
            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                self?.playBufferMilliSec -= msec
            }
        }
        receive()
    }
}
