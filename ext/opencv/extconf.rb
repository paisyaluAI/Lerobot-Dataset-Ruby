require 'mkmf'

dir_config("opencv")

pkg_config('opencv4')

# C++17を使用
$CXXFLAGS ||= ""
$CXXFLAGS += " -std=c++17"

have_library('stdc++')

create_header()
create_makefile('libopencv')
