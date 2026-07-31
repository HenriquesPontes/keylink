require 'xcodeproj'
project = Xcodeproj::Project.open('./keycard.xcodeproj')
test_target = project.targets.find { |t| t.name == 'keycardTests' }
test_target.build_configuration_list.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
end
project.save
