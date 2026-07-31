import Foundation
import Combine

class OTAUpdateManager: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var isUpdating: Bool = false
    @Published var updateStatus: String = "Idle"
    @Published var updateError: String? = nil

    func startUpdate(fileURL: URL) {
        guard fileURL.startAccessingSecurityScopedResource() else {
            DispatchQueue.main.async {
                self.updateError = "Permission denied to read the firmware file."
                self.updateStatus = "Failed"
            }
            return
        }
        
        defer { fileURL.stopAccessingSecurityScopedResource() }
        
        guard let fileData = try? Data(contentsOf: fileURL) else {
            DispatchQueue.main.async {
                self.updateError = "Failed to read the firmware file."
                self.updateStatus = "Failed"
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isUpdating = true
            self.progress = 0.0
            self.updateStatus = "Connecting to ESP32..."
            self.updateError = nil
        }
        
        guard let url = URL(string: "http://192.168.4.1/update") else {
            DispatchQueue.main.async {
                self.updateError = "Invalid URL."
                self.updateStatus = "Failed"
                self.isUpdating = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"update\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        
        let session = URLSession(configuration: configuration, delegate: OTAUploadDelegate(manager: self), delegateQueue: nil)
        
        let task = session.uploadTask(with: request, from: body) { data, response, error in
            DispatchQueue.main.async {
                self.isUpdating = false
                
                if let error = error {
                    self.updateError = error.localizedDescription
                    self.updateStatus = "Failed"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    if let data = data, let responseString = String(data: data, encoding: .utf8), responseString == "OK" {
                        self.updateStatus = "Success! Rebooting..."
                        self.progress = 1.0
                    } else {
                        self.updateError = "Update failed on ESP32."
                        self.updateStatus = "Failed"
                    }
                } else {
                    self.updateError = "Server returned an error."
                    self.updateStatus = "Failed"
                }
            }
        }
        
        task.resume()
    }
}

class OTAUploadDelegate: NSObject, URLSessionTaskDelegate {
    weak var manager: OTAUpdateManager?
    
    init(manager: OTAUpdateManager) {
        self.manager = manager
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async {
            self.manager?.progress = progress
            self.manager?.updateStatus = "Uploading (\(Int(progress * 100))%)"
        }
    }
}
