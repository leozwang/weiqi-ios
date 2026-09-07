import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        #if targetEnvironment(simulator)
        applySimulatorPatches()
        #endif
        _ = SoundManager.shared
        if #available(iOS 13, *) {
            // SceneDelegate will handle window
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
            let rootVC = ViewController()
            window?.rootViewController = rootVC
            window?.makeKeyAndVisible()
        }
        
        return true
    }

    // MARK: UISceneSession Lifecycle
    @available(iOS 13.0, *)
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

#if targetEnvironment(simulator)
private func applySimulatorPatches() {
    // 1. Swizzle MTLDebugDevice newResidencySetWithDescriptor:error: to avoid failed assertion on simulator with Metal validation
    if let debugDeviceClass = NSClassFromString("MTLDebugDevice") {
        let sel = NSSelectorFromString("newResidencySetWithDescriptor:error:")
        if let method = class_getInstanceMethod(debugDeviceClass, sel) {
            let block: @convention(block) (AnyObject, AnyObject?, UnsafeMutablePointer<AnyObject?>?) -> AnyObject? = { _, _, _ in
                return nil
            }
            let newImp = imp_implementationWithBlock(block)
            method_setImplementation(method, newImp)
        }
    }
}
#endif
