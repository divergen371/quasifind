  $ mkdir -p test_cli_dir
  $ cd test_cli_dir

  $ mkdir -p normal_dir/sub_dir
  $ touch normal_dir/sub_dir/target.txt
  $ touch normal_dir/another.txt
  $ mkdir -p .git/objects
  $ touch .git/config
  $ mkdir -p node_modules/react
  $ touch node_modules/react/index.js

  $ mkdir -p link_target
  $ touch link_target/secret.md
  $ ln -s link_target my_symlink

  $ quasifind . 'name =~ "target.txt"'
  ./normal_dir/sub_dir/target.txt

  $ quasifind -E ".git" -E "node_modules" . 'size >= 0' | sort
  ./link_target
  ./link_target/secret.md
  ./my_symlink
  ./normal_dir
  ./normal_dir/another.txt
  ./normal_dir/sub_dir
  ./normal_dir/sub_dir/target.txt

  $ quasifind -d 1 . 'size >= 0' | sort
  ./link_target
  ./my_symlink
  ./normal_dir

  $ quasifind . 'name =~ "secret.md"' | sort
  ./link_target/secret.md

  $ quasifind -L . 'name =~ "secret.md"' | sort
  ./link_target/secret.md

  $ dd if=/dev/zero of=normal_dir/big_file.bin bs=1024 count=2048 2>/dev/null
  $ quasifind . 'name =~ ".*\.bin" && size > 1MB'
  ./normal_dir/big_file.bin

  $ cd ..
  $ rm -rf test_cli_dir
