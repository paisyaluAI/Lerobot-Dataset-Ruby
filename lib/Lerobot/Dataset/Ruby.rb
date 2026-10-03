# frozen_string_literal: true

begin
  require "libopencv"
rescue LoadError
  ext_so = File.expand_path("../../../ext/opencv/libopencv", __dir__)
  require ext_so if File.exist?("#{ext_so}.so")
end

require_relative "Ruby/reader"
require_relative "Ruby/writer"

module Lerobot
  module Dataset
    module Ruby
      VERSION = "0.2.0"
      class Error < StandardError; end
    end
  end
end
