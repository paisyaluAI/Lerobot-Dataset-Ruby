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

# Python実行環境の解決 (同階層のlerobotやConda環境、venvに対応)
sibling_lerobot = File.expand_path('../../lerobot/src', __dir__)
python_bin = nil
env_setup = ""

if File.exist?(File.expand_path('../.venv/bin/activate', __dir__))
  env_setup = ". \"#{File.expand_path('../.venv/bin/activate', __dir__)}\" && "
  python_bin = "python"
elsif File.executable?(File.expand_path('../../miniforge3/envs/lerobot/bin/python', __dir__))
  python_bin = File.expand_path('../../miniforge3/envs/lerobot/bin/python', __dir__)
elsif File.executable?(File.expand_path('~/miniforge3/envs/lerobot/bin/python'))
  python_bin = File.expand_path('~/miniforge3/envs/lerobot/bin/python')
elsif ENV['CONDA_PREFIX'] && File.executable?(File.join(ENV['CONDA_PREFIX'], 'bin', 'python'))
  python_bin = File.join(ENV['CONDA_PREFIX'], 'bin', 'python')
else
  python_bin = "python3"
end

python_path_export = File.directory?(sibling_lerobot) ? "export PYTHONPATH=\"#{sibling_lerobot}:$PYTHONPATH\" && " : ""

system(
  'bash', '-lc',
  "cd #{File.expand_path('..', __dir__)} && #{env_setup}#{python_path_export}#{python_bin} - <<'PY'\n#{python_code}\nPY"
)

exit($?.exitstatus)
