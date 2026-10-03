require_relative '../lib/lerobot'

# データセット書き込みインスタンス作成
writer = LeRobotDatasetWriter.new(output_dir: File.expand_path('../output_dataset/robot_dataset', __dir__), fps: 30)

# カメラをオープン（外部からソースを指定）
puts "カメラをオープン中..."
# Libopencv.open(0)
# Libopencv.open_mp4('./public/test.mp4')
Libopencv.open_mp4(File.expand_path('../test/test.mp4', __dir__))

# 録画開始（ファイル名はWriterのデフォルトを使用）
writer.start_recording

# 10エピソード
10.times do |j|

  # エピソード開始（タスク指定）
  writer.start_episode(task: "Grab the black cube")

  # 10フレーム撮影・録画・データ保存
  10.times do |i|
    # カメラから画像取得
    image_bytes = Libopencv.take_picture
    
    if image_bytes
      # LeRobot データセットにも保存（v3形式）
      writer.add_frame(
        action: [0.1 * i, 0.2 * i],
        state: [1.0, 0.5],
        image_bytes: image_bytes,
        timestamp: i.to_f / 30
      )
      
      puts "フレーム #{i} を保存しました"
    else
      puts "フレーム #{i} の取得に失敗"
    end
  end

  # エピソード保存
  writer.save_episode

end

# 録画停止（Libopencvの呼び出しはWriter内部で実行）
writer.stop_recording

# ウィンドウ破棄
Libopencv.destroy_window

# データセット保存（Parquet書き込み）
writer.save

puts "完了！"