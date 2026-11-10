import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var awgControl: AwgControl?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    awgControl = AwgControl(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
