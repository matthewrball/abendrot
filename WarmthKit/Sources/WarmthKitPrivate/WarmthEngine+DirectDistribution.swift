import DisplayServices
import HardwareDDC
import NightShiftBridge
import OverlayRenderer
import WarmthKit

extension WarmthEngine {
    public static func directDistribution(configuration: EngineConfiguration) -> WarmthEngine {
        let store = FileDDCSnapshotStore()
        return WarmthEngine(
            configuration: configuration,
            overlay: OverlayBackend(),
            gamma: GammaBackend(),
            ddc: IOAVServiceDDCTransport(store: store),
            snapshotStore: store,
            nightShiftFollower: SystemNightShiftStateFollower(),
            injectedDisplays: nil
        )
    }
}

extension FileDDCSnapshotStore: WarmthSnapshotStore {}
extension SystemNightShiftStateFollower: NightShiftStateFollowing {}
