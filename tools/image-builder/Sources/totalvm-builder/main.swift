import Foundation

// totalvm-builder — boots a Linux RAW disk under Apple's Virtualization
// framework so cloud-init can provision it into a TotalVM image.
//
//   totalvm-builder run \
//       --disk   build/work/developer.raw \
//       --seed   build/work/seed.iso \
//       --share  provision=images/developer-ubuntu/provision \
//       --share  assets=images/developer-ubuntu/assets \
//       --cpus 4 --memory 4096
//
// The process exits 0 when the guest powers itself off (provisioning done).

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(64)
}

func usage() -> Never {
    let text = """
    totalvm-builder — minimal Linux VM runner (Apple Virtualization framework)

    USAGE:
      totalvm-builder run [options]

    OPTIONS:
      --disk <path>        RAW disk image to boot (read/write)         [required]
      --seed <path>        Read-only cloud-init seed image (ISO)
      --boot-seed          Present the seed before the main disk for rescue boot
      --share <tag=path>   Expose a host directory via virtiofs (repeatable)
      --cpus <n>           Virtual CPU count                            [default: 4]
      --memory <mb>        Memory in MiB                                [default: 4096]
      --interactive        Put the terminal in raw mode (manual console use)
      -h, --help           Show this help

    The runner exits 0 when the guest powers itself off.
    """
    print(text)
    exit(0)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
if command == "-h" || command == "--help" { usage() }
guard command == "run" else { fail("unknown command '\(command)' (try --help)") }
args.removeFirst()

var diskPath: String?
var seedPath: String?
var shares: [Share] = []
var cpus = 4
var memoryMB: UInt64 = 4096
var interactive = false
var bootSeed = false

func next(_ name: String) -> String {
    guard !args.isEmpty else { fail("missing value for \(name)") }
    return args.removeFirst()
}

while !args.isEmpty {
    let flag = args.removeFirst()
    switch flag {
    case "--disk": diskPath = next(flag)
    case "--seed": seedPath = next(flag)
    case "--cpus":
        guard let n = Int(next(flag)), n > 0 else { fail("--cpus must be a positive integer") }
        cpus = n
    case "--memory":
        guard let m = UInt64(next(flag)), m >= 512 else { fail("--memory must be >= 512 (MiB)") }
        memoryMB = m
    case "--interactive":
        interactive = true
    case "--boot-seed":
        bootSeed = true
    case "--share":
        let spec = next(flag)
        guard let eq = spec.firstIndex(of: "=") else { fail("--share expects tag=path, got '\(spec)'") }
        let tag = String(spec[..<eq])
        let path = String(spec[spec.index(after: eq)...])
        guard !tag.isEmpty, !path.isEmpty else { fail("--share expects tag=path, got '\(spec)'") }
        shares.append(Share(tag: tag, path: path, readOnly: false))
    case "-h", "--help":
        usage()
    default:
        fail("unknown option '\(flag)'")
    }
}

guard let disk = diskPath else { fail("--disk is required") }
guard FileManager.default.fileExists(atPath: disk) else { fail("disk not found: \(disk)") }
if let seed = seedPath, !FileManager.default.fileExists(atPath: seed) {
    fail("seed not found: \(seed)")
}
for share in shares where !FileManager.default.fileExists(atPath: share.path) {
    fail("share path not found: \(share.path)")
}

let runner = VMRunner(options: RunnerOptions(
    diskPath: disk,
    seedPath: seedPath,
    shares: shares,
    cpuCount: cpus,
    memoryMB: memoryMB,
    interactive: interactive,
    bootSeed: bootSeed
))

do {
    try runner.run()
} catch {
    fail("\(error)")
}
