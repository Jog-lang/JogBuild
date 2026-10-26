# jog.mod: a small SDL game
module game
version 0.3.0
kind executable
jog 0.0.1

require sdl ../sdl                          # a module folder next to this one
require mathx ../vendor/mathx-1.2.0.jogz    # a local archive, unpacked into the cache
require json 1.4.0                          # a version, already in the cache

link m                                      # every native target
link.windows ws2_32
