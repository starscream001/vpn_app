require 'xcodeproj'
require 'fileutils'
root = File.expand_path('..', __dir__)
platform = ARGV[0] || 'ios'
abort 'unsupported platform' unless %w[ios macos].include?(platform)
ios = File.join(root, platform)
project = Xcodeproj::Project.open(File.join(ios, 'Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' }
name = 'AWGPacketTunnel'
target = project.targets.find { |t| t.name == name } || project.new_target(:app_extension, name, platform == 'macos' ? :osx : :ios, platform == 'macos' ? '12.0' : '15.0')
group = project.main_group.find_subpath(name, true)
group.set_source_tree('<group>')
group.path = name
Dir.glob(File.join(ios, name, '*.swift')).each do |path|
  basename = File.basename(path)
  ref = group.files.find { |f| f.path == basename } || group.new_file(basename)
  target.source_build_phase.add_file_reference(ref, true)
end
# A local package allows the exact copied upstream source to be reviewed and built offline.
package = project.root_object.package_references.find { |p| p.respond_to?(:relative_path) && p.relative_path == '../native/amnezia-apple' }
unless package
  package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  package.relative_path = '../native/amnezia-apple'
  project.root_object.package_references << package
end
unless target.package_product_dependencies.any? { |p| p.product_name == 'WireGuardKit' }
  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.package = package
  product.product_name = 'WireGuardKit'
  target.package_product_dependencies << product
  build = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build.product_ref = product
  target.frameworks_build_phase.files << build
end
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'app.foxway.foxway.AWGPacketTunnel',
    'PRODUCT_NAME' => name, 'SWIFT_VERSION' => '5.0', 'IPHONEOS_DEPLOYMENT_TARGET' => '15.0',
    'MACOSX_DEPLOYMENT_TARGET' => '12.0',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'SKIP_INSTALL' => 'YES',
    'CODE_SIGN_ENTITLEMENTS' => "#{name}/#{name}.entitlements", 'INFOPLIST_FILE' => "#{name}/Info.plist",
    'LIBRARY_SEARCH_PATHS' => ['$(inherited)', '$(SRCROOT)/../native/amnezia-apple/Sources/WireGuardKitGo/out'],
    'OTHER_LDFLAGS' => ['$(inherited)', '-lwg-go', '-lresolv'], 'TARGETED_DEVICE_FAMILY' => '1,2',
    'MARKETING_VERSION' => '0.2.0', 'CURRENT_PROJECT_VERSION' => '2'
  })
end
runner.add_dependency(target) unless runner.dependencies.any? { |d| d.target == target }
phase = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' } || runner.new_copy_files_build_phase('Embed Foundation Extensions')
phase.dst_subfolder_spec = '13'
unless phase.files.any? { |f| f.file_ref == target.product_reference }
  entry = phase.add_file_reference(target.product_reference)
  entry.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
end
if (thin = runner.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' })
  runner.build_phases.delete(phase)
  runner.build_phases.insert(runner.build_phases.index(thin), phase)
end
host_group = project.main_group.find_subpath('Runner', false)
ref = host_group.files.find { |f| f.path == 'AwgControl.swift' } || host_group.new_file('AwgControl.swift')
runner.source_build_phase.add_file_reference(ref, true)
keychain = '$(AppIdentifierPrefix)app.foxway.shared'
host_entitlements = platform == 'macos' ? ['Runner/DebugProfile.entitlements', 'Runner/Release.entitlements'] : ['Runner/Runner.entitlements']
(host_entitlements + ["#{name}/#{name}.entitlements"]).each do |relative|
  path = File.join(ios, relative)
  data = File.exist?(path) ? Xcodeproj::Plist.read_from_path(path) : {}
  data['com.apple.developer.networking.networkextension'] = ['packet-tunnel-provider']
  data['com.apple.security.application-groups'] = ['group.app.foxway.foxway']
  data['keychain-access-groups'] = (['$(AppIdentifierPrefix)$(CFBundleIdentifier)'] + (data['keychain-access-groups'] || []) + [keychain]).uniq
  if platform == 'macos' && relative.start_with?(name)
    data['com.apple.security.app-sandbox'] = true
    data['com.apple.security.network.client'] = true
    data['com.apple.security.network.server'] = true
  end
  Xcodeproj::Plist.write_to_path(data, path)
end
runner_info = File.join(ios, 'Runner/Info.plist')
data = Xcodeproj::Plist.read_from_path(runner_info)
data['FoxWayKeychainGroup'] = keychain
Xcodeproj::Plist.write_to_path(data, runner_info)
Xcodeproj::Plist.write_to_path({
  'CFBundleDisplayName' => 'FoxWay AmneziaWG', 'CFBundleName' => '$(PRODUCT_NAME)',
  'CFBundleExecutable' => '$(EXECUTABLE_NAME)', 'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)',
  'CFBundlePackageType' => 'XPC!', 'CFBundleShortVersionString' => '$(MARKETING_VERSION)',
  'CFBundleVersion' => '$(CURRENT_PROJECT_VERSION)', 'FoxWayKeychainGroup' => keychain,
  'NSExtension' => { 'NSExtensionPointIdentifier' => 'com.apple.networkextension.packet-tunnel',
    'NSExtensionPrincipalClass' => '$(PRODUCT_MODULE_NAME).PacketTunnelProvider' }
}, File.join(ios, name, 'Info.plist'))
project.save
puts 'Configured AWG extension and shared Keychain; no keys stored in provider preferences'
