  $ mkdir -p test_dummy_dir
  $ cd test_dummy_dir

  $ touch .hidden_file
  $ touch .AnotherHidden
  $ mkdir .hidden_dir
  $ touch normal_file.txt
  $ mkdir NormalDir
  $ touch file_A
  $ touch file_b

  $ ln -s normal_file.txt symlink_to_file
  $ ln -s NormalDir symlink_to_dir
  $ ln normal_file.txt hardlink_to_file

  $ quasifind --ls . | awk '{print $1, $NF}'
  .rw-r--r-- .AnotherHidden
  drwxr-xr-x .hidden_dir
  .rw-r--r-- .hidden_file
  .rw-r--r-- file_A
  .rw-r--r-- file_b
  .rw-r--r-- hardlink_to_file
  .rw-r--r-- normal_file.txt
  drwxr-xr-x NormalDir
  lrwxr-xr-x symlink_to_dir
  lrwxr-xr-x symlink_to_file

  $ cd ..
  $ rm -rf test_dummy_dir
