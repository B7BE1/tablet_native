import UIKit

class ViewController: UIViewController, URLSessionWebSocketDelegate {
    
    private let imageView = UIImageView()
    private var webSocket: URLSessionWebSocketTask?
    
    // Mouse tracking variables
    private var lastTouchPoint: CGPoint?
    private let sensitivity: CGFloat = 1.0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleToFill // Stretch to fill like osu! expects
        view.addSubview(imageView)
        
        // Enable multi-touch if needed, but for osu! one pencil is enough
        view.isMultipleTouchEnabled = false
        
        connectWebSocket()
    }
    
    override var prefersStatusBarHidden: Bool { return true }
    override var prefersHomeIndicatorAutoHidden: Bool { return true }
    
    // MARK: - Networking
    
    private func connectWebSocket() {
        // Connect to localhost (pymobiledevice3 forwards 8765 from PC to iPad over USB)
        let url = URL(string: "ws://127.0.0.1:8765")!
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        
        receiveMessage()
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    // We received a JPEG frame
                    if let image = UIImage(data: data) {
                        DispatchQueue.main.async {
                            self.imageView.image = image
                        }
                    }
                case .string(_):
                    break
                @unknown default:
                    break
                }
                
                // Immediately queue next read
                self.receiveMessage()
                
            case .failure(let error):
                print("WebSocket disconnected: \(error)")
                // Reconnect after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.connectWebSocket()
                }
            }
        }
    }
    
    private func send(string: String) {
        let message = URLSessionWebSocketTask.Message.string(string)
        webSocket?.send(message) { error in
            if let error = error {
                print("Send error: \(error)")
            }
        }
    }
    
    // MARK: - Touch Handling (Apple Pencil & Finger)
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        lastTouchPoint = touch.location(in: view)
        
        // Send left click down
        send(string: "1,1,0,0")
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let last = lastTouchPoint else { return }
        
        // Get all coalesced touches for 240Hz iPad Pro polling!
        let coalescedTouches = event?.coalescedTouches(for: touch) ?? [touch]
        
        var currentLast = last
        var accumulatedDx: CGFloat = 0
        var accumulatedDy: CGFloat = 0
        
        for cTouch in coalescedTouches {
            let loc = cTouch.location(in: view)
            accumulatedDx += (loc.x - currentLast.x) * sensitivity
            accumulatedDy += (loc.y - currentLast.y) * sensitivity
            currentLast = loc
        }
        
        lastTouchPoint = currentLast
        
        let dx = Int(accumulatedDx)
        let dy = Int(accumulatedDy)
        
        if dx != 0 || dy != 0 {
            send(string: "1,0,\(dx),\(dy)")
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouchPoint = nil
        // Send left click up
        send(string: "1,2,0,0")
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
