import UIKit
import Network

class ViewController: UIViewController {
    
    private let imageView = UIImageView()
    private var listener: NWListener?
    private var connection: NWConnection?
    
    // Mouse tracking variables
    private var lastTouchPoint: CGPoint?
    private let sensitivity: CGFloat = 1.0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleToFill
        view.addSubview(imageView)
        
        view.isMultipleTouchEnabled = false
        
        startWebSocketServer()
    }
    
    override var prefersStatusBarHidden: Bool { return true }
    override var prefersHomeIndicatorAutoHidden: Bool { return true }
    
    // MARK: - Networking (iPad as Server)
    
    private func startWebSocketServer() {
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        
        do {
            listener = try NWListener(using: parameters, on: 8765)
            listener?.newConnectionHandler = { [weak self] newConnection in
                self?.connection = newConnection
                newConnection.start(queue: .main)
                self?.receiveMessage(on: newConnection)
            }
            listener?.start(queue: .main)
            print("Server started on port 8765")
        } catch {
            print("Failed to start listener: \(error)")
        }
    }
    
    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] completeContent, contentContext, isComplete, error in
            if let data = completeContent, !data.isEmpty {
                // Determine if it's binary (image) or text
                if let wsMetadata = contentContext?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                    if wsMetadata.opcode == .binary {
                        if let image = UIImage(data: data) {
                            DispatchQueue.main.async {
                                self?.imageView.image = image
                            }
                        }
                    }
                }
            }
            
            if error == nil {
                self?.receiveMessage(on: connection)
            } else {
                print("Connection closed")
                self?.connection = nil
            }
        }
    }
    
    private func send(string: String) {
        guard let connection = connection else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        
        connection.send(content: string.data(using: .utf8), contentContext: context, isComplete: true, completion: .contentProcessed({ error in
            if let error = error {
                print("Send error: \(error)")
            }
        }))
    }
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: view)
        let nx = loc.x / view.bounds.width
        let ny = loc.y / view.bounds.height
        send(string: "2,\(nx),\(ny),1") // 1 = touch down
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let coalescedTouches = event?.coalescedTouches(for: touch) ?? [touch]
        
        for cTouch in coalescedTouches {
            let loc = cTouch.location(in: view)
            let nx = loc.x / view.bounds.width
            let ny = loc.y / view.bounds.height
            send(string: "2,\(nx),\(ny),2") // 2 = move
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: view)
        let nx = loc.x / view.bounds.width
        let ny = loc.y / view.bounds.height
        send(string: "2,\(nx),\(ny),0") // 0 = touch up
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
