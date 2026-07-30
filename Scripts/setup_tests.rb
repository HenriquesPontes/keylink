require 'xcodeproj'

project_path = './keylink.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 1. Create the test target
main_target = project.targets.find { |t| t.name == 'keylink' }
if main_target.nil?
  puts "Could not find 'keylink' target"
  exit 1
end

# Check if it already exists
if project.targets.find { |t| t.name == 'keylinkTests' }
  puts "keylinkTests target already exists!"
  exit 0
end

test_target = project.new_target(:unit_test_bundle, 'keylinkTests', :ios)
test_target.build_configuration_list.set_setting('PRODUCT_BUNDLE_IDENTIFIER', 'com.livlu.keylinkTests')
test_target.build_configuration_list.set_setting('INFOPLIST_FILE', 'keylinkTests/Info.plist')
test_target.build_configuration_list.set_setting('TEST_HOST', '$(BUILT_PRODUCTS_DIR)/keylink.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/keylink')
test_target.build_configuration_list.set_setting('BUNDLE_LOADER', '$(TEST_HOST)')
test_target.build_configuration_list.set_setting('TARGETED_DEVICE_FAMILY', '1,2')
test_target.build_configuration_list.set_setting('SWIFT_VERSION', '5.0')
test_target.build_configuration_list.set_setting('IPHONEOS_DEPLOYMENT_TARGET', '17.0')
test_target.build_configuration_list.set_setting('DEVELOPMENT_TEAM', main_target.build_configuration_list.build_configurations.first.build_settings['DEVELOPMENT_TEAM'])
test_target.build_configuration_list.set_setting('CODE_SIGN_STYLE', 'Automatic')

# 2. Add dependency on main target
test_target.add_dependency(main_target)

# 3. Create the group and directory
group = project.main_group.find_subpath(File.join('keylinkTests'), true)
group.set_source_tree('<group>')
group.set_path('keylinkTests')

# 4. Add the Info.plist and Test file (we will create them on disk next)
file_ref = group.new_reference('CardImportManagerTests.swift')
test_target.source_build_phase.add_file_reference(file_ref)

info_ref = group.new_reference('Info.plist')

# Save project
project.save
puts "Added keylinkTests target successfully!"
