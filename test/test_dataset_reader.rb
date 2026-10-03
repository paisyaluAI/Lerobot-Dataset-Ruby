# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

class TestLeRobotDatasetReader < Minitest::Test
  def setup
    @root = Dir.mktmpdir('lerobot-reader-test-')
    writer = LeRobotDatasetWriter.new(output_dir: @root, fps: 30)
    2.times do |episode_index|
      writer.start_episode(task: "task-#{episode_index}")
      2.times do |frame_index|
        writer.add_frame(
          action: [frame_index.to_f],
          state: [episode_index.to_f],
          timestamp: frame_index.to_f / 30
        )
      end
      writer.save_episode
    end
    writer.save
    @reader = LeRobotDatasetReader.new(@root)
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_reads_episode_frames_separately
    assert_equal @reader.info['total_episodes'], @reader.episode_count
    assert_equal @reader.info['total_frames'], @reader.frame_count

    first = @reader.episode(0)
    assert_equal 0, first[:episode_index]
    assert_equal first[:length], first[:frames].length
    assert_equal 0, first[:frames].first[:episode_index]
  end

  def test_unknown_episode_raises
    assert_raises(IndexError) { @reader.episode(999_999) }
  end

  def test_frame_index_continues_across_episodes
    assert_equal [0, 1], @reader.episode(0)[:frames].map { |frame| frame[:frame_index] }
    assert_equal [2, 3], @reader.episode(1)[:frames].map { |frame| frame[:frame_index] }
  end

  def test_unsaved_episode_is_excluded_from_dataset
    writer = LeRobotDatasetWriter.new(output_dir: @root, fps: 30)
    2.times do |episode_index|
      writer.start_episode(task: "task-#{episode_index}")
      2.times do |frame_index|
        writer.add_frame(
          action: [frame_index.to_f],
          state: [episode_index.to_f],
          timestamp: frame_index.to_f / 30
        )
      end
      writer.save_episode
    end

    writer.start_episode(task: 'discarded-task')
    2.times do |frame_index|
      writer.add_frame(action: [frame_index.to_f], state: [2.0])
    end
    writer.save_episode(save: false)
    writer.save
    reader = LeRobotDatasetReader.new(@root)

    assert_equal 2, reader.episode_count
    assert_equal [0, 1], reader.episode(0)[:frames].map { |frame| frame[:frame_index] }
    assert_equal [2, 3], reader.episode(1)[:frames].map { |frame| frame[:frame_index] }
    assert_equal [1, 1], reader.episode(1)[:frames].map { |frame| frame[:episode_index] }
  end

  def test_new_episode_after_unsaved_episode_keeps_video_frame_index_unique
    writer = LeRobotDatasetWriter.new(output_dir: @root, fps: 30)
    2.times do |episode_index|
      writer.start_episode(task: "task-#{episode_index}")
      writer.add_frame(action: [0.0], state: [episode_index.to_f])
      writer.save_episode
    end

    writer.start_episode(task: 'discarded-task')
    writer.add_frame(action: [0.0], state: [3.0])
    writer.save_episode(save: false)
    writer.start_episode(task: 'new-task')
    writer.add_frame(action: [0.0], state: [4.0])
    writer.save_episode
    writer.save
    reader = LeRobotDatasetReader.new(@root)

    assert_equal [0, 1, 3], reader.each_frame.map { |frame| frame['frame_index'] }
  end
end