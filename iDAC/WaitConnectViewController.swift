//
//  WaitConnectViewController.swift
//  iDAC
//
//  Created by user on 2021/08/08.
//

import UIKit
import Network
import AVKit

class WaitConnectViewController: UIViewController {
    
    let listener: NWListener = {
        var tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        var params = NWParameters.init(tls: nil, tcp: tcpOptions)
        params.serviceClass = .interactiveVoice
        params.acceptLocalOnly = true
        return try! NWListener(using: params, on: 48000)
    }()
    
    override func loadView() {
        view = UIView()
        let label = UILabel()
        label.text = "Waiting New Connection..."
        view.addSubview(label)
        label.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        label.textColor = .white
        view.backgroundColor = .darkGray
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005)
        } catch {
            print(error)
        }
        
        listener.newConnectionHandler = { conn in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    return
                }
                self.present(UINavigationController(rootViewController: MainViewController(connection: conn)), animated: true, completion: nil)
            }
        }
        listener.start(queue: .global(qos: .userInteractive))
    }
}
