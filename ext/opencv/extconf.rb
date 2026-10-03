require 'mkmf'

dir_config("opencv")

pkg_config('opencv4')
create_header()
create_makefile('libopencv')
