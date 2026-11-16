#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require_relative '../lib/lerobot'

root = File.expand_path('../output_dataset/robot_dataset', __dir__)
FileUtils.rm_rf(root)

writer = LeRobotDatasetWriter.new(output_dir: root, fps: 30)
writer.start_episode(task: 'Grab the black cube')

3.times do |i|
  writer.add_frame(
    action: [0.1 * (i + 1), 0.2 * (i + 1)],
    state: [1.0, 0.5],
    timestamp: i.to_f / 30.0
  )
end

writer.save_episode
writer.save
video_file = File.join(root, 'videos', 'rgb', 'chunk-000', 'file-000.mp4')
unless File.exist?(video_file)
  system("ffmpeg -f lavfi -i color=c=black:s=640x480:r=30 -frames:v 3 -c:v libx264 -pix_fmt yuv420p #{video_file} -y -loglevel error")
end
puts "Ruby dataset generated at: #{root}"

python_code = <<~PY
  import json
  from pathlib import Path
  from lerobot.datasets.lerobot_dataset import LeRobotDataset

  root = Path(r"#{root}")
  print("root_exists", root.exists())
  ds = LeRobotDataset(repo_id="lerobot_min_check", root=root)
  print("len", len(ds))
  print("tasks", ds.meta.tasks.to_dict())
  sample = ds[0]
  print("sample_keys", sorted(sample.keys()))
  print("timestamp", sample["timestamp"])
  print("action", sample["action"])
  print("state", sample["state"])
PY

# Python実行環境の解決 (ワークスペース共通の robot-stack/.venv またはローカル .venv に対応)
sibling_lerobot = File.expand_path('../../../third_party/lerobot/src', __dir__)
workspace_venv_activate = File.expand_path('../../../.venv/bin/activate', __dir__)
local_venv_activate = File.expand_path('../.venv/bin/activate', __dir__)
python_bin = nil
env_setup = ""

if File.exist?(workspace_venv_activate)
  env_setup = ". \"#{workspace_venv_activate}\" && "
  python_bin = "python"
elsif File.exist?(local_venv_activate)
  env_setup = ". \"#{local_venv_activate}\" && "
  python_bin = "python"
elsif ENV['VIRTUAL_ENV'] && File.executable?(File.join(ENV['VIRTUAL_ENV'], 'bin', 'python'))
  python_bin = File.join(ENV['VIRTUAL_ENV'], 'bin', 'python')
else
  python_bin = "python3"
end

python_path_export = File.directory?(sibling_lerobot) ? "export PYTHONPATH=\"#{sibling_lerobot}:$PYTHONPATH\" && " : ""

system(
  'bash', '-lc',
  "cd #{File.expand_path('..', __dir__)} && #{env_setup}#{python_path_export}#{python_bin} - <<'PY'\n#{python_code}\nPY"
)

exit($?.exitstatus)
