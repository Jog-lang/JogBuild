# libdir and require.test
module game
version 0.3.0
kind executable
jog 0.0.1

require mathx ../vendor/mathx-1.2.0.jogz
require.test mock_fs ./mocks/mock_fs

libdir ./vendor/lib
libdir.linux ./prefix/lib64
libdir.macos ./prefix/lib
libdir.windows ./prefix/lib
