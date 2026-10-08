Pod::Spec.new do |s|
  s.name = 'IosEnhancements'
  s.version = '0.1.0'
  s.summary = 'RustDesk iOS orientation and optional userspace Tailnet integration'
  s.homepage = 'https://github.com/rustdesk/rustdesk'
  s.license = { :type => 'AGPL-3.0', :file => '../../../LICENCE' }
  s.author = 'RustDesk contributors'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.{swift,h}'
  s.public_header_files = 'Classes/EmbeddedTailnet.h'
  s.vendored_libraries = 'libEmbeddedTailnet.a'
  s.resources = 'THIRD-PARTY-NOTICES.txt'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.static_framework = true
  s.frameworks = 'Security', 'SystemConfiguration', 'CoreFoundation'
  s.libraries = 'resolv'
end
