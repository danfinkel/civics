#!/usr/bin/env ruby
# Add libllama.dylib to Xcode project

require 'xcodeproj'

project_path = File.expand_path('Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.find { |t| t.name == 'Runner' }
unless target
  puts "Error: Could not find Runner target"
  exit 1
end

# Check if libllama.dylib already exists in the project
libllama_ref = project.files.find { |f| f.path == 'Frameworks/libllama.dylib' }

if libllama_ref.nil?
  # Add the library file reference
  framework_group = project.groups.find { |g| g.name == 'Frameworks' } || project.main_group
  libllama_ref = framework_group.new_file('Frameworks/libllama.dylib')
  puts "Added libllama.dylib file reference"
else
  puts "libllama.dylib file reference already exists"
end

# Check if already in "Link Binary With Libraries" build phase
link_phase = target.frameworks_build_phase
already_linked = link_phase.files_references.include?(libllama_ref)

unless already_linked
  link_phase.add_file_reference(libllama_ref)
  puts "Added libllama.dylib to 'Link Binary With Libraries'"
else
  puts "libllama.dylib already in 'Link Binary With Libraries'"
end

# Check if already in "Embed Frameworks" build phase
embed_phase = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
if embed_phase.nil?
  # Create the embed frameworks phase if it doesn't exist
  embed_phase = target.new_copy_files_build_phase('Embed Frameworks')
  embed_phase.dst_subfolder_spec = Xcodeproj::Constants::PBXCopyFilesBuildPhase::DST_FRAMEWORKS
end

already_embedded = embed_phase.files_references.include?(libllama_ref)

unless already_embedded
  build_file = embed_phase.add_file_reference(libllama_ref)
  build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
  puts "Added libllama.dylib to 'Embed Frameworks' with CodeSignOnCopy"
else
  puts "libllama.dylib already in 'Embed Frameworks'"
end

# Add LIBRARY_SEARCH_PATHS to all build configurations
['Debug', 'Release', 'Profile'].each do |config_name|
  config = target.build_settings(config_name)
  if config
    config['LIBRARY_SEARCH_PATHS'] = ['$(inherited)', '$(PROJECT_DIR)/Frameworks']
    puts "Added LIBRARY_SEARCH_PATHS to #{config_name}"
  end
end

# Save the project
project.save
puts "Project saved successfully"
