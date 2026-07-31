require 'xcodeproj'

project_path = './keycard.xcodeproj'
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == 'keycard' }
if main_target.nil?
  puts "Could not find 'keycard' target"
  exit 1
end

if project.targets.find { |t| t.name == 'keycardWidget' }
  puts "keycardWidget target already exists!"
  exit 0
end

widget_target = project.new_target(:app_extension, 'keycardWidget', :ios)
widget_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.livlu.keycard.keycardWidget'
  config.build_settings['INFOPLIST_FILE'] = 'keycardWidget/Info.plist'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['PRODUCT_NAME'] = 'keycardWidget'
end
widget_target.build_configuration_list.set_setting('IPHONEOS_DEPLOYMENT_TARGET', '17.0')
widget_target.build_configuration_list.set_setting('DEVELOPMENT_TEAM', main_target.build_configuration_list.build_configurations.first.build_settings['DEVELOPMENT_TEAM'])
widget_target.build_configuration_list.set_setting('CODE_SIGN_STYLE', 'Automatic')
widget_target.build_configuration_list.set_setting('SKIP_INSTALL', 'YES')

widget_target.add_system_framework('WidgetKit')
widget_target.add_system_framework('SwiftUI')
widget_target.add_system_framework('ActivityKit')

main_target.add_dependency(widget_target)

embed_phase = main_target.build_phases.find { |p| p.class == Xcodeproj::Project::Object::PBXCopyFilesBuildPhase && p.name == 'Embed Foundation Extensions' }
if embed_phase.nil?
  embed_phase = main_target.new_copy_files_build_phase('Embed Foundation Extensions')
  embed_phase.dst_subfolder_spec = '13' # Plugins
end
file_ref = widget_target.product_reference
build_file = embed_phase.add_file_reference(file_ref)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

group = project.main_group.groups.find { |g| g.path == 'keycardWidget' || g.name == 'keycardWidget' }
if group.nil?
  group = project.main_group.new_group('keycardWidget', 'keycardWidget')
end

info_ref = group.new_reference('Info.plist')
widget_ref = group.new_reference('keycardWidget.swift')
attr_ref = group.new_reference('EmulationAttributes.swift')

widget_target.source_build_phase.add_file_reference(widget_ref)
widget_target.source_build_phase.add_file_reference(attr_ref)

# Also add EmulationAttributes.swift to the main app target so it can start the activity
main_target.source_build_phase.add_file_reference(attr_ref)

project.save
puts "Added keycardWidget target successfully!"
