import Foundation
import Virtualization

/// A single virtiofs shared directory exposed to the guest.
struct Share {
    let tag: String
    let path: String
    let readOnly: Bool
}

/// Everything needed to boot one Linux VM for provisioning.
struct RunnerOptions {
    var diskPath: String
    var seedPath: String?
    var shares: [Share] = []
    var cpuCount: Int
    var memoryMB: UInt64
    var interactive: Bool
    var bootSeed: Bool
}

/// Minimal headless Linux VM built on Apple's Virtualization framework.
///
/// The runner boots a RAW disk (plus an optional read-only cloud-init seed
/// image), streams the guest serial console to stdout/stderr, and terminates
/// the process when the guest powers itself off — which is exactly how the
/// provisioning flow signals "image is ready".
final class VMRunner: NSObject, VZVirtualMachineDelegate {

    private let options: RunnerOptions
    private var virtualMachine: VZVirtualMachine?
    private var originalTerminal: termios?

    init(options: RunnerOptions) {
        self.options = options
    }

    // MARK: - Configuration

    private func makeConfiguration() throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()

        config.cpuCount = options.cpuCount
        config.memorySize = options.memoryMB * 1024 * 1024

        // EFI boot with a persistent NVRAM store kept next to the disk so the
        // boot entry written by the guest installer survives reboots.
        let bootLoader = VZEFIBootLoader()
        let nvramURL = URL(fileURLWithPath: options.diskPath + ".nvram")
        if FileManager.default.fileExists(atPath: nvramURL.path) {
            bootLoader.variableStore = VZEFIVariableStore(url: nvramURL)
        } else {
            bootLoader.variableStore = try VZEFIVariableStore(creatingVariableStoreAt: nvramURL)
        }
        config.bootLoader = bootLoader
        config.platform = VZGenericPlatformConfiguration()

        // Storage: main RAW disk + optional read-only cloud-init seed.
        var storage: [VZStorageDeviceConfiguration] = []
        // Image builds perform sustained package extraction and must never
        // observe stale host-cache pages. Disable host data caching and honor
        // every guest flush before continuing; throughput is secondary to a
        // byte-correct release image.
        let mainAttachment = try VZDiskImageStorageDeviceAttachment(
            url: URL(fileURLWithPath: options.diskPath),
            readOnly: false,
            cachingMode: .uncached,
            synchronizationMode: .full
        )
        var seedDevice: VZVirtioBlockDeviceConfiguration?
        if let seedPath = options.seedPath {
            let seedAttachment = try VZDiskImageStorageDeviceAttachment(
                url: URL(fileURLWithPath: seedPath),
                readOnly: true
            )
            seedDevice = VZVirtioBlockDeviceConfiguration(attachment: seedAttachment)
        }
        if options.bootSeed, let seedDevice {
            storage.append(seedDevice)
            storage.append(VZVirtioBlockDeviceConfiguration(attachment: mainAttachment))
        } else {
            storage.append(VZVirtioBlockDeviceConfiguration(attachment: mainAttachment))
            if let seedDevice {
                storage.append(seedDevice)
            }
        }
        config.storageDevices = storage

        // Serial console wired to this process's stdio.
        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        serial.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: FileHandle.standardInput,
            fileHandleForWriting: FileHandle.standardOutput
        )
        config.serialPorts = [serial]

        // NAT networking so apt / npm / docker pulls work during provisioning.
        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [network]

        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        // A virtio-gpu so the guest gets a /dev/dri DRM node, exactly like the
        // TotalVM app. The build itself is headless (no window is attached), but
        // matching the app's hardware means the desktop stack (Xorg/lightdm) can
        // be provisioned and verified against a real GPU.
        let graphics = VZVirtioGraphicsDeviceConfiguration()
        graphics.scanouts = [
            VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1920, heightInPixels: 1080)
        ]
        config.graphicsDevices = [graphics]

        // Match TotalVM's runtime hardware during provisioning. In particular,
        // this lets the Arch build verify that its out-of-tree virtio-snd
        // driver creates a real ALSA card before an image is published.
        let audioOutput = VZVirtioSoundDeviceOutputStreamConfiguration()
        audioOutput.sink = VZHostAudioOutputStreamSink()
        let audio = VZVirtioSoundDeviceConfiguration()
        audio.streams = [audioOutput]
        config.audioDevices = [audio]

        // virtiofs shares — used to hand the provisioning scripts and assets
        // to the guest without baking them into the seed image.
        config.directorySharingDevices = options.shares.map { share in
            let device = VZVirtioFileSystemDeviceConfiguration(tag: share.tag)
            device.share = VZSingleDirectoryShare(
                directory: VZSharedDirectory(
                    url: URL(fileURLWithPath: share.path),
                    readOnly: share.readOnly
                )
            )
            return device
        }

        try config.validate()
        return config
    }

    // MARK: - Lifecycle

    func run() throws {
        let config = try makeConfiguration()
        let vm = VZVirtualMachine(configuration: config)
        vm.delegate = self
        self.virtualMachine = vm

        if options.interactive {
            enableRawTerminal()
        }
        installSignalHandlers()

        vm.start { result in
            switch result {
            case .success:
                FileHandle.standardError.write(Data("[totalvm-builder] VM started\n".utf8))
            case .failure(let error):
                FileHandle.standardError.write(Data("[totalvm-builder] start failed: \(error)\n".utf8))
                self.restoreTerminal()
                exit(2)
            }
        }

        RunLoop.main.run()
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        FileHandle.standardError.write(Data("[totalvm-builder] guest stopped with error: \(error)\n".utf8))
        restoreTerminal()
        exit(3)
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        FileHandle.standardError.write(Data("[totalvm-builder] guest powered off cleanly\n".utf8))
        restoreTerminal()
        exit(0)
    }

    // MARK: - Signals & terminal

    private func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { _ in
            // Best-effort: just restore the terminal and leave. The disk stays
            // intact for a retry.
            var raw = termios()
            tcgetattr(STDIN_FILENO, &raw)
            exit(130)
        }
        signal(SIGINT, handler)
        signal(SIGTERM, handler)
    }

    private func enableRawTerminal() {
        guard isatty(STDIN_FILENO) != 0 else { return }
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        originalTerminal = raw
        cfmakeraw(&raw)
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    }

    private func restoreTerminal() {
        guard var original = originalTerminal else { return }
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
        originalTerminal = nil
    }
}
