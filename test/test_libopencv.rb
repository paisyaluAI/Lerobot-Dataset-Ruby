# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../ext/opencv/libopencv' if File.exist?(File.expand_path('../ext/opencv/libopencv.so', __dir__))

class TestLibopencv < Minitest::Test
  def test_module_defined
    assert_includes Object.constants, :Libopencv
  end

  def test_methods_defined
    assert_respond_to Libopencv, :open_mp4
    assert_respond_to Libopencv, :cam_open
    assert_respond_to Libopencv, :start_recording
    assert_respond_to Libopencv, :take_picture
    assert_respond_to Libopencv, :write_frame
    assert_respond_to Libopencv, :stop_recording
    assert_respond_to Libopencv, :show_movie
    assert_respond_to Libopencv, :wait_key
    assert_respond_to Libopencv, :destroy_window
  end

  def test_recording_state_errors
    # 録画開始せずにフレーム書き込みを試みると例外が発生すること
    assert_raises(RuntimeError) do
      Libopencv.write_frame("dummy")
    end
  end

  def test_start_recording_invalid_args
    # カメラを開かずに録画開始すると例外が発生すること
    assert_raises(RuntimeError) do
      Libopencv.start_recording("test.mp4", 30.0)
    end
    # 引数が不正な場合に例外が発生すること
    assert_raises(ArgumentError) do
      Libopencv.start_recording(nil, 30.0)
    end
    assert_raises(ArgumentError) do
      Libopencv.start_recording("test.mp4", -1)
    end
  end

  def test_cam_open_invalid_args
    assert_raises(ArgumentError) do
      Libopencv.cam_open(0, 0, 480)
    end
    assert_raises(ArgumentError) do
      Libopencv.cam_open(0, 640, -1)
    end
  end
end
