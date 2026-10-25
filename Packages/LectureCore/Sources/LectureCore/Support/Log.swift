#if canImport(os)
import os

/// 앱 로그. Console.app에서 subsystem으로 걸러 볼 수 있다.
public enum Log {
    public static let subsystem = "com.uisong.LectureRecorder"
    public static let data = Logger(subsystem: subsystem, category: "data")
    public static let recording = Logger(subsystem: subsystem, category: "recording")
    public static let playback = Logger(subsystem: subsystem, category: "playback")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
#endif
