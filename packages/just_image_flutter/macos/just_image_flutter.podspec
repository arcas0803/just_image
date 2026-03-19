Pod::Spec.new do |s|
  s.name             = 'just_image_flutter'
  s.version          = '0.0.1'
  s.summary          = 'macOS support for just_image_flutter'
  s.description      = 'Native code is provided via Dart Native Assets. This podspec is a placeholder.'
  s.homepage         = 'https://github.com/just-image/just_image'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'just_image' => 'just_image@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
