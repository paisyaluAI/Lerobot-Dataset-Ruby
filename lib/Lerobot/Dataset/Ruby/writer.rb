# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'parquet'

module Lerobot
  module Dataset
    module Ruby
      class Writer
        attr_reader :output_dir, :fps

        def initialize(output_dir:, fps: 30, tasks: nil)
          @output_dir = File.expand_path(output_dir)
          @fps = fps
          @episodes = []
          @all_frames = []
          @task_map = {}
          @episode_counter = 0
          @next_video_frame_index = 0
          @recording = false

          Array(tasks).each { |task| task_index(task) }

          # v3ディレクトリ構造
          FileUtils.mkdir_p(File.join(@output_dir, 'meta'))
          FileUtils.mkdir_p(File.join(@output_dir, 'data', 'chunk-000'))
          FileUtils.mkdir_p(File.join(@output_dir, 'videos', 'rgb', 'chunk-000'))
          FileUtils.mkdir_p(File.join(@output_dir, 'meta', 'episodes', 'chunk-000'))
        end

        # 録画開始（内部でLibopencvを呼び出す）
        def start_recording(path = nil, fps = nil)
          path ||= File.join(@output_dir, 'videos', 'rgb', 'chunk-000', 'file-000.mp4')
          Libopencv.start_recording(path, fps || @fps)
          image_bytes = Libopencv.take_picture
          Libopencv.write_frame(image_bytes)
          @recording = true
          puts "録画開始: #{path}"
        end

        # 録画停止（内部でLibopencvを呼び出す）
        def stop_recording
          if @recording
            Libopencv.stop_recording
            @recording = false
            puts "録画を停止しました"
          end
        end

        # 新しいエピソードを開始
        def start_episode(task: "Default task")
          @current_episode = {
            episode_index: @episode_counter,
            task: task,
            from_index: @all_frames.length
          }
          @episode_counter += 1
          task_index(task)
        end

        # フレームを追加（現在のエピソードに）
        def add_frame(action:, state:, image_bytes: nil, timestamp: nil)
          unless @current_episode
            raise RuntimeError, "start_episodeを最初に呼び出してください"
          end

          episode_frame_index = @all_frames.length - @current_episode[:from_index]
          frame_data = {
            index: @all_frames.length,
            episode_index: @current_episode[:episode_index],
            frame_index: @next_video_frame_index,
            task_index: task_index(@current_episode[:task]),
            action: action,
            state: state,
            timestamp: timestamp || episode_frame_index.to_f / @fps
          }

          if image_bytes
            # 録画中ならLibopencvに書き込み
            raise RuntimeError, "録画が開始されていません" unless @recording
            Libopencv.write_frame(image_bytes)
          end

          @all_frames << frame_data
          @next_video_frame_index += 1
        end

        # エピソードを保存（save: false なら動画だけ残してデータセットから除外）
        def save_episode(save: true)
          unless @current_episode
            return
          end

          episode = @current_episode

          unless save
            @all_frames.slice!(episode[:from_index], @all_frames.length - episode[:from_index])
            @all_frames.each_with_index { |frame, index| frame[:index] = index }
            @episode_counter -= 1
            @current_episode = nil
            return
          end

          episode_length = @all_frames.length - episode[:from_index]
          episode_frames = @all_frames[episode[:from_index], episode_length] || []
          first_video_frame = episode_frames.first ? episode_frames.first[:frame_index] : @next_video_frame_index
          last_video_frame = episode_frames.last ? episode_frames.last[:frame_index] : first_video_frame - 1

          @episodes << {
            episode_index: episode[:episode_index],
            tasks: [episode[:task]],
            length: episode_length,
            dataset_from_index: episode[:from_index],
            dataset_to_index: @all_frames.length,
            "data/chunk_index" => 0,
            "data/file_index" => 0,
            "videos/rgb/chunk_index" => 0,
            "videos/rgb/file_index" => 0,
            "videos/rgb/from_timestamp" => first_video_frame.to_f / @fps,
            "videos/rgb/to_timestamp" => (last_video_frame + 1).to_f / @fps,
            "meta/episodes/chunk_index" => 0,
            "meta/episodes/file_index" => 0,
            frame_start: episode[:from_index],
            frame_end: @all_frames.length,
            task_index: task_index(episode[:task])
          }

          @current_episode = nil
        end

        # 最終保存（Parquet書き込み）
        def save
          if @current_episode
            save_episode
          end

          ensure_default_video_file
          write_info_json
          write_tasks_parquet
          write_stats_json
          write_episodes_parquet
          write_data_parquet

          puts "Dataset v3.0 successfully created at: #{@output_dir}"
        end

        private

        def task_index(task)
          @task_map[task] ||= @task_map.size
        end

        def ensure_default_video_file
          video_dir = File.join(@output_dir, 'videos', 'rgb', 'chunk-000')
          video_path = File.join(video_dir, 'file-000.mp4')
          FileUtils.mkdir_p(video_dir)

          return video_path if File.exist?(video_path)

          gem_root = File.expand_path('../../../..', __dir__)
          sample_path = [
            File.join(gem_root, 'test', 'test.mp4'),
            File.join(gem_root, 'public', 'test.mp4')
          ].find { |path| File.exist?(path) }

          FileUtils.cp(sample_path, video_path) if sample_path
          video_path
        end

        def write_info_json
          action_size = @all_frames.first&.dig(:action)&.size || 2
          state_size = @all_frames.first&.dig(:state)&.size || 2

          info = {
            codebase_version: "v3.0",
            fps: @fps,
            total_episodes: @episodes.size,
            total_frames: @all_frames.size,
            total_tasks: @task_map.size,
            chunks_size: 1000,
            data_files_size_in_mb: 100,
            video_files_size_in_mb: 200,
            data_path: "data/chunk-{chunk_index:03d}/file-{file_index:03d}.parquet",
            video_path: "videos/{video_key}/chunk-{chunk_index:03d}/file-{file_index:03d}.mp4",
            features: {
              "index" => { "dtype" => "int64", "shape" => [1] },
              "episode_index" => { "dtype" => "int64", "shape" => [1] },
              "frame_index" => { "dtype" => "int64", "shape" => [1] },
              "task_index" => { "dtype" => "int64", "shape" => [1] },
              "action" => { "dtype" => "float32", "shape" => [action_size] },
              "state" => { "dtype" => "float32", "shape" => [state_size] },
              "timestamp" => { "dtype" => "float32", "shape" => [1] },
              "rgb" => { "dtype" => "video", "shape" => [480, 640, 3], "names" => ["height", "width", "channel"] }
            },
            tasks: @task_map.sort_by { |_, index| index }.map(&:first)
          }

          File.write(File.join(@output_dir, 'meta', 'info.json'), JSON.pretty_generate(info))
        end

        def write_tasks_parquet
          parquet_path = File.join(@output_dir, 'meta', 'tasks.parquet')
          schema = Parquet::Schema.define do
            field :task_index, :int64, nullable: false
            field :task, :string, nullable: false
          end

          rows = @task_map.sort_by { |_, index| index }.map do |task_str, index|
            [index, task_str]
          end

          Parquet.write_rows(rows, schema: schema, write_to: parquet_path)
        end

        def write_stats_json
          action_size = @all_frames.first&.dig(:action)&.size || 2
          state_size = @all_frames.first&.dig(:state)&.size || 2
          total_frames = @all_frames.size

          stats = {
            "index" => {
              "mean" => [0],
              "std" => [1],
              "min" => [0],
              "max" => [1],
              "count" => total_frames
            },
            "episode_index" => {
              "mean" => [0],
              "std" => [1],
              "min" => [0],
              "max" => [1],
              "count" => total_frames
            },
            "frame_index" => {
              "mean" => [0],
              "std" => [1],
              "min" => [0],
              "max" => [1],
              "count" => total_frames
            },
            "task_index" => {
              "mean" => [0],
              "std" => [1],
              "min" => [0],
              "max" => [1],
              "count" => total_frames
            },
            "action" => {
              "mean" => Array.new(action_size, 0.0),
              "std" => Array.new(action_size, 1.0),
              "min" => Array.new(action_size, -1.0),
              "max" => Array.new(action_size, 1.0),
              "count" => total_frames
            },
            "state" => {
              "mean" => Array.new(state_size, 0.0),
              "std" => Array.new(state_size, 1.0),
              "min" => Array.new(state_size, -1.0),
              "max" => Array.new(state_size, 1.0),
              "count" => total_frames
            },
            "timestamp" => {
              "mean" => [0.0],
              "std" => [1.0],
              "min" => [0.0],
              "max" => [1.0],
              "count" => total_frames
            }
          }

          File.write(File.join(@output_dir, 'meta', 'stats.json'), JSON.pretty_generate(stats))
        end

        def write_episodes_parquet
          parquet_path = File.join(@output_dir, 'meta', 'episodes', 'chunk-000', 'file-000.parquet')

          schema = Parquet::Schema.define do
            field :episode_index, :int32, nullable: false
            field :tasks, :list, item: :string
            field :length, :int32, nullable: false
            field :dataset_from_index, :int32, nullable: false
            field :dataset_to_index, :int32, nullable: false
            field :"data/chunk_index", :int32, nullable: false
            field :"data/file_index", :int32, nullable: false
            field :"videos/rgb/chunk_index", :int32, nullable: false
            field :"videos/rgb/file_index", :int32, nullable: false
            field :"videos/rgb/from_timestamp", :float
            field :"videos/rgb/to_timestamp", :float
            field :"meta/episodes/chunk_index", :int32, nullable: false
            field :"meta/episodes/file_index", :int32, nullable: false
            field :frame_start, :int32, nullable: false
            field :frame_end, :int32, nullable: false
            field :task_index, :int64, nullable: false
          end

          rows = @episodes.map do |ep|
            [
              ep[:episode_index],
              ep[:tasks],
              ep[:length],
              ep[:dataset_from_index],
              ep[:dataset_to_index],
              ep["data/chunk_index"],
              ep["data/file_index"],
              ep["videos/rgb/chunk_index"],
              ep["videos/rgb/file_index"],
              ep["videos/rgb/from_timestamp"],
              ep["videos/rgb/to_timestamp"],
              ep["meta/episodes/chunk_index"],
              ep["meta/episodes/file_index"],
              ep[:frame_start],
              ep[:frame_end],
              ep[:task_index]
            ]
          end

          Parquet.write_rows(rows, schema: schema, write_to: parquet_path)
        end

        def write_data_parquet
          parquet_path = File.join(@output_dir, 'data', 'chunk-000', 'file-000.parquet')

          schema = Parquet::Schema.define do
            field :index, :int64, nullable: false
            field :episode_index, :int64, nullable: false
            field :frame_index, :int64, nullable: false
            field :task_index, :int64, nullable: false
            field :action, :list, item: :float
            field :state, :list, item: :float
            field :timestamp, :float
          end

          rows = @all_frames.map do |frame|
            [
              frame[:index],
              frame[:episode_index],
              frame[:frame_index],
              frame[:task_index],
              frame[:action],
              frame[:state],
              frame[:timestamp]
            ]
          end

          Parquet.write_rows(rows, schema: schema, write_to: parquet_path)
        end
      end
    end
  end
end

# 後方互換性のためのエイリアス
LeRobotDatasetWriter = Lerobot::Dataset::Ruby::Writer
