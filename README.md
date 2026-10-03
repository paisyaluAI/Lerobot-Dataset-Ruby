# Lerobot-Dataset-Ruby

[![Gem Version](https://badge.fury.io/rb/Lerobot-Dataset-Ruby.svg)](https://rubygems.org/gems/Lerobot-Dataset-Ruby)
[![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.2-red.svg)](https://www.ruby-lang.org/)
[![LeRobot Compatible](https://img.shields.io/badge/Format-LeRobotDataset%20v2%2Fv3-yellow.svg)](https://github.com/huggingface/lerobot)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE.txt)

Hugging Face のロボティクス学習フレームワーク **[LeRobot](https://github.com/huggingface/lerobot)** 形式のデータセット（Parquet + MP4）の記録および読み込みを Ruby で行うための Gem ライブラリです。

高速なカメラ映像キャプチャおよび MP4 録画を可能にする **OpenCV C++ 拡張モジュール** を内包しています。

---

## 🚀 実機・Mock サンプルフレームワーク

本 Gem を組み込んで実際に動作する **4WD ロボットカー制御・自律走行サンプルフレームワーク** を以下のリポジトリで公開しています。

👉 **[https://github.com/paisyaluAI/ruby-teleop-agent](https://github.com/paisyaluAI/ruby-teleop-agent)**

- **テレオペレーション**: ゲームパッドやキーボードで車体を操縦しながら、車載カメラ映像とモーター制御値を LeRobotDataset 形式でリアルタイム記録
- **VLA 自律走行**: SmolVLA 推論サーバーと HTTP 通信を行い、モデルが予測したアクション（チャンク）で車体をリアルタイム自律制御
- **Mock モード**: 実機ハードウェア（Raspberry Pi / Webカメラ / GPIO）がなくてもローカル PC 上で即座に動作検証可能

---

## 前提条件 (システムライブラリ)

本 Gem のインストールおよびビルドには、OpenCV 4 の開発ヘッダーが必要です。

```bash
# Debian / Ubuntu / Raspberry Pi OS
sudo apt-get update
sudo apt-get install -y build-essential ruby-dev libopencv-dev
```

---

## インストール

### RubyGems からインストールする場合

```bash
gem install Lerobot-Dataset-Ruby
```

Bundler を使用する場合は `Gemfile` に追加してください:

```ruby
gem "Lerobot-Dataset-Ruby", "~> 1.0.0"
```

### ローカルソースコードからビルド・インストールする場合

```bash
git clone https://github.com/paisyaluAI/lerobot-dataset-ruby.git
cd lerobot-dataset-ruby
gem build Lerobot-Dataset-Ruby.gemspec
gem install ./Lerobot-Dataset-Ruby-*.gem
```

---

## 使い方 (Usage)

### 1. データセットの記録 (`Writer`)

カメラ映像と左右の操作値（アクション）を記録し、LeRobotDataset 形式（`meta/`, `data/`, `videos/`）で出力します。

```ruby
require 'lerobot-dataset-ruby'

# 初期化 (出力ディレクトリ, 目標FPS)
writer = Lerobot::Dataset::Ruby::Writer.new(
  output_dir: 'output_dataset/my_experiment',
  fps: 10
)

# カメラオープン (ID: 0, 640x480) & 録画開始
Libopencv.cam_open(0, 640, 480)
writer.start_recording

# エピソード開始 (自然言語タスクを付与)
writer.start_episode(task: 'Go to the blue star')

# 制御ループ内でフレームを追加
image_bytes = Libopencv.take_picture
writer.add_frame(
  action: [0.5, 0.5],    # 左右制御値 [-1.0, 1.0]
  state: [0.5, 0.5],     # 現在状態
  image_bytes: image_bytes,
  timestamp: 0.1
)

# エピソード保存
writer.save_episode(save: true)

# 終了処理 (データセット全体の確定)
writer.stop_recording
writer.save
Libopencv.destroy_window
```

### 2. 記録したデータセットの読み込み (`Reader`)

```ruby
require 'lerobot-dataset-ruby'

reader = Lerobot::Dataset::Ruby::Reader.new('output_dataset/my_experiment')

# エピソード 0 を取得
episode = reader.episode(0)
puts "エピソードフレーム数: #{episode[:length]}"

episode[:frames].each do |frame|
  puts "Action: #{frame[:action]}, Timestamp: #{frame[:timestamp]}"
end
```

---

## 開発

```bash
bin/setup
rake test
```

---

## ライセンス

[MIT License](LICENSE.txt)
