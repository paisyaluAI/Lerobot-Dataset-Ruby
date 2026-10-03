# frozen_string_literal: true

require 'json'
require 'parquet'

module Lerobot
  module Dataset
    module Ruby
      # LeRobotDatasetWriter が生成した v3 データセットを読むクラス。
      class Reader
        attr_reader :root, :info, :tasks

        def initialize(root)
          @root = File.expand_path(root)
          @info = load_json('meta/info.json')
          @tasks = load_tasks
          @episodes = read_rows(episode_data_path)
          @frames = read_rows(data_path)
          validate_dataset
        end

        def episode_count
          @episodes.length
        end

        def frame_count
          @frames.length
        end

        def episodes
          @episodes.map { |episode| episode_metadata(episode) }
        end

        def episode(index)
          episode = find_episode(index)
          from_index = integer_value(episode['dataset_from_index'])
          to_index = integer_value(episode['dataset_to_index'])

          {
            episode_index: integer_value(episode['episode_index']),
            tasks: Array(episode['tasks']),
            length: integer_value(episode['length']),
            frames: @frames[from_index...to_index].map { |frame| normalize_frame(frame) }
          }
        end

        def each_episode
          return enum_for(__method__) unless block_given?

          @episodes.each do |episode|
            yield episode_metadata(episode)
          end
        end

        def each_frame(episode_index = nil)
          return enum_for(__method__, episode_index) unless block_given?

          selected = episode_index.nil? ? @frames : episode(episode_index)[:frames]
          selected.each { |frame| yield frame }
        end

        # 指定エピソードを OpenCV ウィンドウで再生する。
        # ブロックには [フレームメタデータ, JPEG バイト列] を渡す。
        def play(episode_index, delay: nil)
          begin
            require 'libopencv'
          rescue LoadError
            require_relative '../../../../ext/opencv/libopencv'
          end

          episode_data = episode(episode_index)
          video_path = File.expand_path(video_relative_path, @root)
          Libopencv.open_mp4(video_path)

          skip_frames(episode_data[:frames].first&.fetch(:frame_index, 0).to_i)
          frame_delay = delay || (1000.0 / @info.fetch('fps', 30)).round

          episode_data[:frames].each do |metadata|
            image_bytes = Libopencv.take_picture
            yield metadata, image_bytes if block_given?
            Libopencv.show_movie
            key = Libopencv.wait_key(frame_delay)
            break if key == 27 || key == 113
          end
        ensure
          Libopencv.destroy_window if defined?(Libopencv)
        end

        private

        def load_json(relative_path)
          JSON.parse(File.read(File.join(@root, relative_path)))
        rescue Errno::ENOENT => error
          raise ArgumentError, "データセットのファイルが見つかりません: #{error.path}"
        end

        def load_tasks
          parquet_path = File.join(@root, 'meta', 'tasks.parquet')
          raise ArgumentError, "タスク定義が見つかりません: #{parquet_path}" unless File.file?(parquet_path)

          Parquet.each_row(parquet_path).map do |row|
            { 'task_index' => row['task_index'], 'task' => row['task'] }
          end
        end

        def read_rows(relative_path)
          path = File.join(@root, relative_path)
          raise ArgumentError, "Parquet ファイルが見つかりません: #{path}" unless File.file?(path)

          Parquet.each_row(path).to_a
        end

        def data_path
          @info.dig('data_files', 'data') || 'data/chunk-000/file-000.parquet'
        end

        def episode_data_path
          @info['episode_data_files'] || 'meta/episodes/chunk-000/file-000.parquet'
        end

        def validate_dataset
          declared_frames = @info['total_frames']
          declared_episodes = @info['total_episodes']
          unless declared_frames == @frames.length && declared_episodes == @episodes.length
            raise ArgumentError, 'info.json と Parquet の件数が一致しません'
          end

          @episodes.each do |episode|
            from_index = integer_value(episode['dataset_from_index'])
            to_index = integer_value(episode['dataset_to_index'])
            length = integer_value(episode['length'])
            unless to_index - from_index == length && @frames[from_index...to_index]&.length == length
              raise ArgumentError, "エピソード #{episode['episode_index']} の範囲が不正です"
            end
          end
        end

        def find_episode(index)
          episode = @episodes.find { |item| integer_value(item['episode_index']) == index }
          raise IndexError, "エピソード #{index} が見つかりません" unless episode

          episode
        end

        def episode_metadata(episode)
          episode.transform_keys(&:to_sym).merge(
            episode_index: integer_value(episode['episode_index']),
            length: integer_value(episode['length'])
          )
        end

        def normalize_frame(frame)
          frame.transform_keys(&:to_sym)
        end

        def integer_value(value)
          Integer(value)
        end

        def video_relative_path
          @info.dig('data_files', 'videos', 'rgb') ||
            'videos/rgb/chunk-000/file-000.mp4'
        end

        def skip_frames(count)
          count.times { Libopencv.take_picture }
        end
      end
    end
  end
end

# 後方互換性のためのエイリアス
LeRobotDatasetReader = Lerobot::Dataset::Ruby::Reader
