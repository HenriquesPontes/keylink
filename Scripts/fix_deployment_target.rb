require 'xcodeproj'
project = Xcodeproj::Project.open('./keycard.xcodeproj')
test_target = project.targets.find { |t| t.name == 'keycardTests' }
main_target = project.targets.find { |t| t.name == 'keycard' }
deployment_target = main_target.build_configuration_list.build_configurations.first.build_settings['IPHONEOS_DEPLOYMENT_TARGET']

test_target.build_configuration_list.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
end
project.save
