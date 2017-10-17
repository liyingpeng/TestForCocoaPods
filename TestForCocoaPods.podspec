Pod::Spec.new do |s|
  s.name         = "TestForCocoaPods" # 项目名称
  s.version      = "0.0.1"        # 版本号 与 你仓库的 标签号 对应
  s.license      = { :type => "MIT", :file => "LICENSE" }          # 开源证书
  s.summary      = "A meaningful utility TestForCocoaPods" # 项目简介

  s.homepage     = "https://github.com/liyingpeng/TestForCocoaPods" # 你的主页
  s.source       = { :git => "https://github.com/liyingpeng/TestForCocoaPods.git", :tag => "0.0.1", :commit => "329112761bc3746ac8637c1c47a293192d9dab96" }#你的仓库地址，不能用SSH地址
  s.source_files  = "Classes/**/*.{h,m}"
  s.requires_arc = true # 是否启用ARC
  s.platform     = :ios, "7.0" #平台及支持的最低版本
  # s.frameworks   = "UIKit", "Foundation" #支持的框架
  # s.dependency   = "AFNetworking" # 依赖库
  
  # User
  s.author             = { "李应鹏" => "liyingpeng@bytedance.com" } # 作者信息

end
