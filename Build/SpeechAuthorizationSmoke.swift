#if os(macOS)
import Foundation
import Speech

@main
struct SpeechAuthorizationSmoke {
    static func main() async {
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    let status = await LocalOnDeviceTranscriber.authorizationStatus {
                        callback in
                        DispatchQueue.global(qos: .userInitiated).async {
                            callback(index.isMultiple(of: 2) ? .authorized : .denied)
                        }
                    }
                    let expected: SFSpeechRecognizerAuthorizationStatus =
                        index.isMultiple(of: 2) ? .authorized : .denied
                    precondition(status == expected)
                }
            }
        }
        print("SPEECH_AUTHORIZATION_BACKGROUND_CALLBACK_PASS")
    }
}
#endif
