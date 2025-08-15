import UIKit
import AVFoundation
import Photos

class SlowMotionCameraViewController: UIViewController {
    
    // MARK: - UI Components
    @IBOutlet weak var cameraPreviewView: UIView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var frameRateLabel: UILabel!
    @IBOutlet weak var frameRateSlider: UISlider!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var playbackView: UIView!
    @IBOutlet weak var playbackButton: UIButton!
    @IBOutlet weak var stabilizationSegmentedControl: UISegmentedControl!
    @IBOutlet weak var stabilizationStatusLabel: UILabel!
    
    // MARK: - AVFoundation Properties
    private var captureSession: AVCaptureSession!
    private var videoDevice: AVCaptureDevice!
    private var videoDeviceInput: AVCaptureDeviceInput!
    private var movieFileOutput: AVCaptureMovieFileOutput!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    // MARK: - Recording Properties
    private var isRecording = false
    private var recordedVideoURL: URL?
    private var selectedFrameRate: Float64 = 240.0
    private var currentStabilizationMode: AVCaptureVideoStabilizationMode = .auto
    
    // MARK: - Playback Properties
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
        checkCameraPermissions()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = cameraPreviewView.bounds
        playerLayer?.frame = playbackView.bounds
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "Slow Motion Camera"
        
        // Record button styling
        recordButton.layer.cornerRadius = 10
        recordButton.backgroundColor = .systemRed
        recordButton.setTitle("Record", for: .normal)
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        
        // Frame rate slider setup
        frameRateSlider.minimumValue = 60
        frameRateSlider.maximumValue = 240
        frameRateSlider.value = Float(selectedFrameRate)
        frameRateSlider.addTarget(self, action: #selector(frameRateSliderChanged), for: .valueChanged)
        
        // Playback button
        playbackButton.setTitle("Play Slow Motion", for: .normal)
        playbackButton.backgroundColor = .systemBlue
        playbackButton.layer.cornerRadius = 10
        playbackButton.addTarget(self, action: #selector(playbackButtonTapped), for: .touchUpInside)
        playbackButton.isEnabled = false
        
        // Stabilization control setup
        stabilizationSegmentedControl.removeAllSegments()
        stabilizationSegmentedControl.insertSegment(withTitle: "Off", at: 0, animated: false)
        stabilizationSegmentedControl.insertSegment(withTitle: "Standard", at: 1, animated: false)
        stabilizationSegmentedControl.insertSegment(withTitle: "Cinematic", at: 2, animated: false)
        stabilizationSegmentedControl.insertSegment(withTitle: "Auto", at: 3, animated: false)
        stabilizationSegmentedControl.selectedSegmentIndex = 3 // Default to Auto
        stabilizationSegmentedControl.addTarget(self, action: #selector(stabilizationModeChanged), for: .valueChanged)
        
        updateStabilizationStatus()
        
        updateFrameRateLabel()
        statusLabel.text = "Ready to record"
        
        // Add borders to preview views
        cameraPreviewView.layer.borderWidth = 2
        cameraPreviewView.layer.borderColor = UIColor.systemBlue.cgColor
        
        playbackView.layer.borderWidth = 2
        playbackView.layer.borderColor = UIColor.systemGreen.cgColor
        playbackView.backgroundColor = .black
    }
    
    // MARK: - Camera Setup
    private func setupCamera() {
        captureSession = AVCaptureSession()
        
        // Configure session for high quality
        captureSession.sessionPreset = .high
        
        // Setup video device (back camera)
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                      for: .video,
                                                      position: .back) else {
            showAlert(title: "Error", message: "Unable to access back camera")
            return
        }
        
        videoDevice = backCamera
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if captureSession.canAddInput(videoDeviceInput) {
                captureSession.addInput(videoDeviceInput)
            }
            
            // Setup movie file output
            movieFileOutput = AVCaptureMovieFileOutput()
            if captureSession.canAddOutput(movieFileOutput) {
                captureSession.addOutput(movieFileOutput)
            }
            
            // Setup preview layer
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            cameraPreviewView.layer.addSublayer(previewLayer)
            
            // Configure initial frame rate and stabilization
            configureFrameRate(selectedFrameRate)
            configureVideoStabilization()
            
        } catch {
            showAlert(title: "Error", message: "Unable to create video device input: \(error.localizedDescription)")
        }
    }
    
    private func configureFrameRate(_ frameRate: Float64) {
        guard let device = videoDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Find the best format for the desired frame rate
            let bestFormat = findBestFormat(for: device, targetFrameRate: frameRate)
            
            if let format = bestFormat {
                device.activeFormat = format
                
                // Set the frame rate
                device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(frameRate))
                device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(frameRate))
                
                statusLabel.text = "Frame rate configured: \(Int(frameRate)) fps"
            } else {
                statusLabel.text = "Unable to set \(Int(frameRate)) fps, using default"
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error configuring frame rate: \(error)")
            statusLabel.text = "Error setting frame rate"
        }
    }
    
    private func findBestFormat(for device: AVCaptureDevice, targetFrameRate: Float64) -> AVCaptureDevice.Format? {
        var bestFormat: AVCaptureDevice.Format?
        
        for format in device.formats {
            let ranges = format.videoSupportedFrameRateRanges
            
            for range in ranges {
                if range.maxFrameRate >= targetFrameRate {
                    // Prefer formats that support the exact frame rate
                    if bestFormat == nil || range.maxFrameRate >= targetFrameRate {
                        bestFormat = format
                    }
                }
            }
        }
        
        return bestFormat
    }
    
    private func configureVideoStabilization() {
        guard let movieFileOutput = movieFileOutput else { return }
        
        // Get the video connection
        guard let videoConnection = movieFileOutput.connection(with: .video) else {
            print("No video connection found")
            return
        }
        
        // Check if stabilization is supported
        if videoConnection.isVideoStabilizationSupported {
            // Check which stabilization modes are supported
            let supportedModes = getSupportedStabilizationModes(for: videoConnection)
            let modeNames = supportedModes.map {
                switch $0 {
                case .off: "off";
                case .standard: "standard";
                case .cinematic: "cinematic";
                case .cinematicExtended: "cinematicExtended";
                case .previewOptimized: "previewOptimized";
                case .cinematicExtendedEnhanced: "cinematicExtendedEnhanced";
                case .auto: "auto";
                default: "unknown"
                }
            }
            print("Supported stabilization modes: \(modeNames)")
            
            // Set the preferred stabilization mode
            if supportedModes.contains(currentStabilizationMode) {
                videoConnection.preferredVideoStabilizationMode = currentStabilizationMode
                print("Set stabilization mode to: \(stabilizationModeString(currentStabilizationMode))")
            } else {
                // Fallback to the best available mode
                let fallbackMode = selectBestAvailableStabilizationMode(from: supportedModes)
                videoConnection.preferredVideoStabilizationMode = fallbackMode
                currentStabilizationMode = fallbackMode
                print("Fallback to stabilization mode: \(stabilizationModeString(fallbackMode))")
            }
            
            updateStabilizationStatus()
        } else {
            print("Video stabilization not supported on this device")
            stabilizationStatusLabel.text = "Stabilization: Not supported"
        }
    }
    
    private func getSupportedStabilizationModes(for connection: AVCaptureConnection) -> [AVCaptureVideoStabilizationMode] {
        var supportedModes: [AVCaptureVideoStabilizationMode] = []
        
        // Test each mode
        let allModes: [AVCaptureVideoStabilizationMode] = [.off, .standard, .cinematic, .auto]
        
        for mode in allModes {
            let originalMode = connection.preferredVideoStabilizationMode
            connection.preferredVideoStabilizationMode = mode
            
            if connection.activeVideoStabilizationMode == mode || mode == .off {
                supportedModes.append(mode)
            }
            
            // Restore original mode
            connection.preferredVideoStabilizationMode = originalMode
        }
        
        return supportedModes
    }
    
    private func selectBestAvailableStabilizationMode(from modes: [AVCaptureVideoStabilizationMode]) -> AVCaptureVideoStabilizationMode {
        // Priority order: cinematic > auto > standard > off
        if modes.contains(.cinematic) { return .cinematic }
        if modes.contains(.auto) { return .auto }
        if modes.contains(.standard) { return .standard }
        return .off
    }
    
    private func stabilizationModeString(_ mode: AVCaptureVideoStabilizationMode) -> String {
        switch mode {
        case .off: return "Off"
        case .standard: return "Standard"
        case .cinematic: return "Cinematic"
        case .auto: return "Auto"
        @unknown default: return "Unknown"
        }
    }
    
    private func updateStabilizationStatus() {
        let modeString = stabilizationModeString(currentStabilizationMode)
        stabilizationStatusLabel.text = "Stabilization: \(modeString)"
        
        // Update segmented control to match current mode
        switch currentStabilizationMode {
        case .off: stabilizationSegmentedControl.selectedSegmentIndex = 0
        case .standard: stabilizationSegmentedControl.selectedSegmentIndex = 1
        case .cinematic: stabilizationSegmentedControl.selectedSegmentIndex = 2
        case .auto: stabilizationSegmentedControl.selectedSegmentIndex = 3
        @unknown default: break
        }
    }
    
    // MARK: - Permissions
    private func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.captureSession.startRunning()
                    }
                }
            }
        case .denied, .restricted:
            showAlert(title: "Camera Access Denied",
                     message: "Please enable camera access in Settings to use this app.")
        @unknown default:
            break
        }
    }
    
    // MARK: - Recording Actions
    @objc private func recordButtonTapped() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard let movieFileOutput = movieFileOutput else { return }
        
        // Create output file URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                   in: .userDomainMask)[0]
        let outputURL = documentsPath.appendingPathComponent("slowmotion_\(Date().timeIntervalSince1970).mov")
        
        // Start recording
        movieFileOutput.startRecording(to: outputURL, recordingDelegate: self)
        
        isRecording = true
        recordButton.setTitle("Stop", for: .normal)
        recordButton.backgroundColor = .systemRed
        statusLabel.text = "Recording at \(Int(selectedFrameRate)) fps..."
        frameRateSlider.isEnabled = false
    }
    
    private func stopRecording() {
        movieFileOutput.stopRecording()
        isRecording = false
        recordButton.setTitle("Record", for: .normal)
        recordButton.backgroundColor = .systemGreen
        statusLabel.text = "Processing video..."
        frameRateSlider.isEnabled = true
    }
    
    // MARK: - Frame Rate Control
    @objc private func frameRateSliderChanged() {
        let newFrameRate = Float64(frameRateSlider.value)
        
        // Round to common frame rates
        let commonRates: [Float64] = [60, 120, 240]
        let closest = commonRates.min { abs($0 - newFrameRate) < abs($1 - newFrameRate) } ?? 240
        
        selectedFrameRate = closest
        frameRateSlider.value = Float(selectedFrameRate)
        
        updateFrameRateLabel()
        configureFrameRate(selectedFrameRate)
        configureVideoStabilization() // Reconfigure stabilization after frame rate change
    }
    
    @objc private func stabilizationModeChanged() {
        let selectedIndex = stabilizationSegmentedControl.selectedSegmentIndex
        
        switch selectedIndex {
        case 0: currentStabilizationMode = .off
        case 1: currentStabilizationMode = .standard
        case 2: currentStabilizationMode = .cinematic
        case 3: currentStabilizationMode = .auto
        default: currentStabilizationMode = .auto
        }
        
        configureVideoStabilization()
        
        // Provide user feedback about stabilization capabilities
        if !isRecording {
            checkStabilizationCompatibility()
        }
    }
    
    private func checkStabilizationCompatibility() {
        guard let movieFileOutput = movieFileOutput,
              let videoConnection = movieFileOutput.connection(with: .video) else { return }
        
        if !videoConnection.isVideoStabilizationSupported {
            showAlert(title: "Stabilization Not Available",
                     message: "Video stabilization is not supported on this device or current configuration.")
            return
        }
        
        // Check if current mode works with current frame rate
        let supportedModes = getSupportedStabilizationModes(for: videoConnection)
        
        if !supportedModes.contains(currentStabilizationMode) {
            let availableModes = supportedModes.map { stabilizationModeString($0) }.joined(separator: ", ")
            showAlert(title: "Stabilization Mode Unavailable",
                     message: "The selected stabilization mode is not available at \(Int(selectedFrameRate)) fps. Available modes: \(availableModes)")
        }
    }
    
    private func updateFrameRateLabel() {
        frameRateLabel.text = "Frame Rate: \(Int(selectedFrameRate)) fps"
    }
    
    // MARK: - Playback
    @objc private func playbackButtonTapped() {
        guard let videoURL = recordedVideoURL else { return }
        
        // Remove existing player
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        
        // Create new player
        player = AVPlayer(url: videoURL)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = playbackView.bounds
        playerLayer?.videoGravity = .resizeAspectFill
        
        playbackView.layer.addSublayer(playerLayer!)
        
        // Calculate slow motion rate from actual video metadata
        calculateSlowMotionRateFromMetadata(videoURL: videoURL) { [weak self] slowMotionRate in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Apply the calculated slow motion rate
                self.player?.play()
                self.player?.rate = slowMotionRate
                
                // Update status with accurate playback info
                let slownessFactor = 1.0 / slowMotionRate
                self.statusLabel.text = String(format: "Playing %.1fx slower (%.3fx speed)", slownessFactor, slowMotionRate)
                
                // Get detailed metadata for debugging
                self.getDetailedVideoMetadata(videoURL: videoURL)
            }
        }
        
        // Loop the video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            // Get the current rate before seeking
            let currentRate = self.player?.rate ?? 0.25
            self.player?.seek(to: .zero)
            self.player?.play()
            self.player?.rate = currentRate // Maintain slow motion rate on loop
        }
    }
    
    private func calculateSlowMotionRate() -> Float {
        let standardFrameRate: Float64 = 30.0
        let slowMotionRate = Float(standardFrameRate / selectedFrameRate)
        return slowMotionRate
    }
    
    private func calculateSlowMotionRateFromMetadata(videoURL: URL, completion: @escaping (Float) -> Void) {
        let asset = AVAsset(url: videoURL)
        
        // Get video tracks
        let videoTracks = asset.tracks(withMediaType: .video)
        
        guard let videoTrack = videoTracks.first else {
            // Fallback to calculated rate if metadata unavailable
            completion(calculateSlowMotionRate())
            return
        }
        
        // Get the nominal frame rate from the video track
        let actualFrameRate = videoTrack.nominalFrameRate
        let standardFrameRate: Float = 30.0
        let slowMotionRate = standardFrameRate / actualFrameRate
        
        print("Video metadata - Actual frame rate: \(actualFrameRate) fps")
        print("Calculated slow motion rate: \(slowMotionRate)")
        
        completion(slowMotionRate)
    }
    
    private func getDetailedVideoMetadata(videoURL: URL) {
        let asset = AVAsset(url: videoURL)
        
        // Get video track for detailed analysis
        guard let videoTrack = asset.tracks(withMediaType: .video).first else { return }
        
        Task {
            do {
                print("\n=== Video Metadata ===")
                print("Nominal Frame Rate: \(videoTrack.nominalFrameRate) fps")
                let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                print("Nominal Frame Rate 2: \(nominalFrameRate) fps")
                print("Natural Time Scale: \(videoTrack.naturalTimeScale)")
                print("Duration: \(CMTimeGetSeconds(asset.duration)) seconds")
                print("Natural Size: \(videoTrack.naturalSize)")
                
                // Check format descriptions for more details
                if let formatDescriptions = videoTrack.formatDescriptions as? [CMVideoFormatDescription] {
                    for description in formatDescriptions {
                        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
                        print("Video Dimensions: \(dimensions.width) x \(dimensions.height)")
                        
                        // Get codec information
                        let codecType = CMFormatDescriptionGetMediaSubType(description)
                        let codecString = String(describing: codecType)
                        print("Codec: \(codecString)")
                    }
                }
                print("======================\n")
            } catch {
                print("error \(error)")
            }
        }
    }
    
    // MARK: - Utility
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
    
    private func saveVideoToPhotoLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.statusLabel.text = "Video saved to Photos"
                    } else {
                        self.statusLabel.text = "Failed to save video: \(error?.localizedDescription ?? "Unknown error")"
                    }
                }
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension SlowMotionCameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                   didFinishRecordingTo outputFileURL: URL,
                   from connections: [AVCaptureConnection],
                   error: Error?) {
        
        DispatchQueue.main.async {
            if let error = error {
                self.statusLabel.text = "Recording error: \(error.localizedDescription)"
            } else {
                self.recordedVideoURL = outputFileURL
                self.statusLabel.text = "Video recorded! Ready for slow motion playback"
                self.playbackButton.isEnabled = true
                
                // Save to photo library
                self.saveVideoToPhotoLibrary(url: outputFileURL)
            }
        }
    }
}
