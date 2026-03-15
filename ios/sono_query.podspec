Pod::Spec.new do |s|
    s.name              = 'sono_query'
    s.version           = '0.1.0'
    s.summary           = 'Audio file discovery and metadata reading for Sono.'
    s.homepage          = 'https://github.com/appsono/sono_query'
    s.license           = { :type => 'MIT'}
    s.author            = { 'Mathis' => '' }
    s.source            = { :git => 'https://github.com/appsono/sono_query.git', :tag s.version.to_s }
    s.source_files      = 'Classes/**/*'
    s.dependency 'Flutter'
    s.platform          = :ios, '12.0'
    s.swift_version     = '5.0'
end 