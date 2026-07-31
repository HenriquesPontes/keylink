require 'xcodeproj'
project_path = 'keycard.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

group = project.main_group.find_subpath(File.join('keycard', 'Utils'), true)

file1 = group.new_file('QRCodeGenerator.swift')
file2 = group.new_file('ScannerView.swift')

target.add_file_references([file1, file2])

project.save
